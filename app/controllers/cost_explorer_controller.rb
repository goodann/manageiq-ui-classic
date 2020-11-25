class CostExplorerController < ApplicationController
  include Mixins::GenericListMixin
  include Mixins::GenericShowMixin
  include Mixins::EmsCommon # common methods for EmsInfra/Cloud controllers
  include Mixins::EmsCommon::Angular
  include Mixins::GenericSessionMixin
  include Mixins::BreadcrumbsMixin


  #include VmCommon # common methods for vm controllers
  #include VmRemote # methods for VM remote access
  #include VmShowMixin
  #include Mixins::BreadcrumbsMixin


  before_action :check_privileges
  before_action :get_session_data
  after_action :cleanup_action
  after_action :set_session_data
  # before_action :check_privileges
  # after_action :cleanup_action

  def self.model
    ManageIQ::Providers::CloudManager
  end

  def show
    #logger.debug("costExplorer.show")
    @breadcrumbs = [{:name => _('Cloud Providers'), :url => '/cost_explorer/show_list'}]
    super
  end

  def ems_path(*args)
    ems_cloud_path(*args)
  end

  def new_ems_path
    new_ems_cloud_path
  end

  def ems_cloud_form_fields
    ems_form_fields
  end

  # Special EmsCloud link builder for restful routes
  def show_link(ems, options = {})
    ems_path(ems.id, options)
  end

  def restful?
    true
  end

  menu_section :clo
  has_custom_buttons

  def sync_users
    ems = find_record_with_rbac(model, params[:id])
    @in_a_form = true
    drop_breadcrumb(:name => _("Sync Users"), :url => "/ems_cloud/sync_users")
    selected_admin_role = params[:admin_role]
    selected_member_role = params[:member_role]
    selected_password = params[:password]
    selected_verify = params[:verify]

    if params[:cancel]
      redirect_to(ems_cloud_path(params[:id]))
      return
    end

    if params[:sync]
      has_error = false
      if selected_password != selected_verify
        add_flash(_("Password/Confirm Password do not match"), :error)
        has_error = true
      end
      if selected_admin_role.blank?
        add_flash(_("An admin role must be selected."), :error)
        has_error = true
      end
      if selected_member_role.blank?
        add_flash(_("A member role must be selected."), :error)
        has_error = true
      end

      if has_error
        render_sync_page(ems, selected_admin_role, selected_member_role, selected_password, selected_verify)
      else
        password_digest = nil
        password_digest = BCrypt::Password.create(selected_password) if selected_password.present?
        ems.sync_users_queue(session[:userid], selected_admin_role, selected_member_role, password_digest)

        flash_to_session(_("Sync users queued."))
        redirect_to(ems_cloud_path(params[:id]))
      end
    else
      render_sync_page(ems, selected_admin_role, selected_member_role, selected_password, selected_verify)
    end
  end

  def render_sync_page(ems, selected_admin_role, selected_member_role, selected_password, selected_verify)
    admin_roles = Rbac::Filterer.filtered(MiqUserRole).pluck(:name, :id).to_h
    member_roles = admin_roles.dup
    admin_roles["Choose Admin Role"] = nil
    member_roles["Choose Member Role"] = nil

    render(:locals => {:selected_admin_role  => selected_admin_role,
                       :selected_member_role => selected_member_role,
                       :selected_password    => selected_password,
                       :selected_verify      => selected_verify,
                       :admin_roles          => admin_roles,
                       :member_roles         => member_roles,
                       :ems                  => ems})
  end

  def breadcrumbs_options
    {
      :breadcrumbs => [
        {:title => _("Compute")},
        {:title => _("Clouds")},
        {:title => _("Providers"), :url => controller_url},
      ],
      :record_info => @ems,
    }.compact
  end


  #########################


  def index
    flash_to_session
    @layout = 'testLayout'
    @page_title = _('test')
    #model = ManageIQ::Providers::Amazon::CloudManager
    require "aws-sdk-ec2"
    require "aws-sdk-costexplorer"
    options = {
      :credentials   => Aws::Credentials.new('AKIAYCDIQG5PAUXZVS5L', '/goHujN7p4+v4WeVK5mTk16tuMAMbO7hvuE+LmbQ'),
      #:region => 'ap-northeast-2', # ENV['AWS_REGION'],
      :region => 'us-east-1',

      #:region => 'ap-northeast-2',
      #:region        => region,
      #:http_proxy    => proxy_uri,
      :logger        => $aws_log,
      :log_level     => :debug,
      :log_formatter => Aws::Log::Formatter.new(Aws::Log::Formatter.default.pattern.chomp),
    }
    # opetions = 
    # {
    #   :credentials => Aws::AssumeRoleCredentials.new(
    #     :client            => Aws::STS::Client.new(options),
    #     :role_arn          => assume_role,
    #     :role_session_name => "ManageIQ-EC2",
    #   ),
    #   :region => 'ap-northeast-2',
    #   #:access_key_id => ,
    # }
    client = Aws::CostExplorer::Client.new(options)

    #Rails.logger.debug model.respond_to?("get_cost_and_usage")


    data = 
    {
      :time_period =>
      {
        :start => "2020-11-02",# required
        :end => "2020-11-04",# required
      },
      :granularity => "DAILY",# accepts DAILY, MONTHLY, HOURLY
      :metrics => [:AmortizedCost, :BlendedCost, :NetAmortizedCost, :NetUnblendedCost, :NormalizedUsageAmount, :UnblendedCost, :UsageQuantity], # required
      :group_by => [
        {
          :type => "DIMENSION", # accepts DIMENSION, TAG, COST_CATEGORY
          :key => "OPERATION",
        },
      ],
      #:next_page_token => "NextPageToken",
    }
    require 'json'
    cost = client.get_cost_and_usage_with_resources(data)
    #logger.debug ("get_cost_and_usage : #{cost}")
    #@layout = 'testLayout'
    #@page_title = _('test')
  end

  def explorer_per_instance
    @is_per_instance=true
    explorer
  end



  def attach
    assert_privileges("instance_attach")
    @volume_choices = {}
    @record = @vm = find_record_with_rbac(VmCloud, params[:id])
    @vm.cloud_tenant.cloud_volumes.where(:status => 'available').each { |v| @volume_choices[v.name] = v.id }
    @in_a_form = true
    drop_breadcrumb(
      :name => _("Attach Cloud Volume to Instance \"%{instance_name}\"") % {:instance_name => @vm.name},
      :url  => "/vm_cloud/attach"
    )
    
    @in_a_form = true
    @refresh_partial = "vm_common/attach"
  end
  alias instance_attach attach

  def detach
    assert_privileges("instance_detach")
    @volume_choices = {}
    @record = @vm = find_record_with_rbac(VmCloud, params[:id])
    attached_volumes = @vm.hardware.disks.select(&:backing).map(&:backing)
    attached_volumes.each { |volume| @volume_choices[volume.name] = volume.id }
    if attached_volumes.empty?
      add_flash(_("Instance \"%{instance_name}\" has no attached Cloud Volumes") % {:instance_name => @vm.name})
      javascript_flash
    end

    @in_a_form = true
    drop_breadcrumb(
      :name => _("Detach Cloud Volume from Instance \"%{instance_name}\"") % {:instance_name => @vm.name},
      :url  => "/vm_cloud/detach"
    )
    @in_a_form = true
    @refresh_partial = "vm_common/detach"
  end
  alias instance_detach detach

  def attach_volume
    assert_privileges("instance_attach")

    @vm = find_record_with_rbac(VmCloud, params[:id])
    case params[:button]
    when "cancel"
      flash_and_redirect(_("Attaching Cloud Volume to Instance \"%{instance_name}\" was cancelled by the user") % {:instance_name => @vm.name})
    when "attach"
      volume = find_record_with_rbac(CloudVolume, params[:volume_id])
      if volume.is_available?(:attach_volume)
        task_id = volume.attach_volume_queue(session[:userid], @vm.ems_ref, params[:device_path])

        if task_id.kind_of?(Integer)
          initiate_wait_for_task(:task_id => task_id, :action => "attach_finished")
        else
          add_flash(_("Attaching Cloud volume failed: Task start failed"), :error)
          javascript_flash(:spinner_off => true)
        end
      else
        add_flash(_(volume.is_available_now_error_message(:attach_volume)), :error)
        javascript_flash
      end
    end
  end

  def attach_finished
    task_id = session[:async][:params][:task_id]
    vm_id = session[:async][:params][:id]
    vm = find_record_with_rbac(VmCloud, vm_id)
    volume_id = session[:async][:params][:volume_id]
    volume = find_record_with_rbac(CloudVolume, volume_id)
    task = MiqTask.find(task_id)
    if MiqTask.status_ok?(task.status)
      add_flash(_("Attaching Cloud Volume \"%{volume_name}\" to %{vm_name} finished") % {
        :volume_name => volume.name,
        :vm_name     => vm.name
      })
    else
      add_flash(_("Unable to attach Cloud Volume \"%{volume_name}\" to %{vm_name}: %{details}") % {
        :volume_name => volume.name,
        :vm_name     => vm.name,
        :details     => get_error_message_from_fog(task.message)
      }, :error)
    end

    @breadcrumbs.pop if @breadcrumbs
    session[:edit] = nil
    flash_to_session
    @record = @sb[:action] = nil
    replace_right_cell
  end

  def detach_volume
    assert_privileges("instance_detach")

    @vm = find_record_with_rbac(VmCloud, params[:id])
    case params[:button]
    when "cancel"
      flash_and_redirect(_("Detaching a Cloud Volume from Instance \"%{instance_name}\" was cancelled by the user") % {:instance_name => @vm.name})

    when "detach"
      volume = find_record_with_rbac(CloudVolume, params[:volume_id])
      if volume.is_available?(:detach_volume)
        task_id = volume.detach_volume_queue(session[:userid], @vm.ems_ref)

        if task_id.kind_of?(Integer)
          initiate_wait_for_task(:task_id => task_id, :action => "detach_finished")
        else
          add_flash(_("Detaching Cloud volume failed: Task start failed"), :error)
          javascript_flash(:spinner_off => true)
        end
      else
        add_flash(_(volume.is_available_now_error_message(:detach_volume)), :error)
        javascript_flash
      end
    end
  end

  def detach_finished
    task_id = session[:async][:params][:task_id]
    vm_id = session[:async][:params][:id]
    vm = find_record_with_rbac(VmCloud, vm_id)
    volume_id = session[:async][:params][:volume_id]
    volume = find_record_with_rbac(CloudVolume, volume_id)
    task = MiqTask.find(task_id)
    if MiqTask.status_ok?(task.status)
      add_flash(_("Detaching Cloud Volume \"%{volume_name}\" from %{vm_name} finished") % {
        :volume_name => volume.name,
        :vm_name     => vm.name
      })
    else
      add_flash(_("Unable to detach Cloud Volume \"%{volume_name}\" from %{vm_name}: %{details}") % {
        :volume_name => volume.name,
        :vm_name     => vm.name,
        :details     => get_error_message_from_fog(task.message)
      }, :error)
    end

    @breadcrumbs.pop if @breadcrumbs
    session[:edit] = nil
    flash_to_session
    @record = @sb[:action] = nil
    replace_right_cell
  end

  def flash_and_redirect(message)
    session[:edit] = nil
    add_flash(message)
    @record = @sb[:action] = nil
    replace_right_cell
  end

  private

  def textual_group_list
    [
        %i[properties] +
          (@record.kind_of?(VmCloud) ? %i[vm_cloud_relationships] : %i[template_cloud_relationships]) +
          %i[labels],
        %i[power_management]
    ]
  end

  helper_method :textual_group_list

  def get_cost_explorer_client
    if @client == nil
      require "aws-sdk-ec2"
      require "aws-sdk-costexplorer"
      #provider_id = @record.id
      #manager = find_record_with_rbac(ExtManagementSystem, provider_id)
      #logger.debug("ExtManagementSystem=#{ExtManagementSystem}")
      
      manager = @record
      userid = manager.authentication_userid
      passwd = manager.authentication_password
      #logger.debug("manager=#{manager.to_json}")
      #ext_mgt_system = ExtManagementSystem.find(manager.id)
      #ext_mgt_system = vm.ext_management_system
      #logger.debug("ext_mgt_system=#{ext_mgt_system.to_json}")
      
      
      #userid = ext_mgt_system.authentication_userid
      #passwd = ext_mgt_system.authentication_password
      #logger.debug ("userid = #{userid}")
      #logger.debug ("passwd = #{passwd}")
      options = {
        :credentials   => Aws::Credentials.new(userid, passwd),
        :region        => 'us-east-1',
        :logger        => $aws_log,
        :log_level     => :debug,
        :log_formatter => Aws::Log::Formatter.new(Aws::Log::Formatter.default.pattern.chomp),
      }
      @client = Aws::CostExplorer::Client.new(options) 
    end

    return @client
  end

  def get_aws_cost_and_usage_data
    if @res != nil && @res_resources != nil
      return @res,@res_resources
    end
    client = get_cost_explorer_client
    data = 
    {
      :time_period =>
      {
        :start => (DateTime.now.utc - 7*3600*24).strftime("%Y-%m-%d"),#"2020-11-01",# required
        :end => (DateTime.now.utc + 1*3600*24).strftime("%Y-%m-%d"),#"2020-11-12",# required
      },
      # :filter =>
      # {
      #   :dimensions => {
      #     :key => :RESOURCE_ID, # required
      #     :values => ["No Resource"], # required
      #     # :key => :SERVICE,
      #     # :values => [
      #     #   "Amazon Elastic Compute Cloud - Compute"
      #     # ],
      #   },
      # },
      :granularity => "DAILY",
      :metrics => [:AmortizedCost], #, :BlendedCost, :NetAmortizedCost, :NetUnblendedCost, :NormalizedUsageAmount, :UnblendedCost, :UsageQuantity], # required
    }
    #logger.debug("data = #{data}")
    @res = client.get_cost_and_usage(data)
    data[:filter] = 
    {
      :dimensions => {
        :key => :SERVICE,
        :values => [
          "Amazon Elastic Compute Cloud - Compute"
        ],
      },
    }
    data[:group_by] =
    [
      {
        :type => "DIMENSION",
        :key => "RESOURCE_ID",
      },
    ]
    @res_resources = client.get_cost_and_usage_with_resources(data)
    
    #@response = [cost_to_summary(res.results_by_time)]
    #return @response
    # @res = res
    # data[:next_token] = res.next_token
    # while res.metric_data_results[0].status_code == "PartialData"
    #   res = client.get_metric_data(data)
    #   @res.metric_data_results[0][:timestamps].concat(res.metric_data_results[0][:timestamps])
    #   @res.metric_data_results[0][:values].concat(res.metric_data_results[0][:values])
    #   data[:next_token] = res.next_token
    # end
    #logger.debug("res = #{@res} ")
    #logger.debug("res_resources = #{@res_resources}")
    return @res,@res_resources
  end

  def textual_group_aws
    res,res_resources = get_aws_cost_and_usage_data
    @response = aws_data_to_summary(res[:results_by_time],res_resources[:results_by_time])
    return @response
  end
  helper_method :textual_group_aws

  def aws_data_to_graph
    res,res_resources=get_aws_cost_and_usage_data
    obj=res[:results_by_time]
    obj_res= res_resources[:results_by_time]
    index = 1
    datalist={}
    stamplist=['x']
    outObj = {}
    day_sum = {}

    ##
    
    obj.each do |day|
      day_sum[day[:time_period][:start]] = day[:total]["AmortizedCost"][:amount].to_f
      stamplist.push(day[:time_period][:start])
    end
    
    ##
    no_resource_data=["No Resource"]

    obj_res.each do |iter|
      day = iter[:time_period][:start][0..9]

      day_sum[day] = 0 if false == day_sum.has_key?(day)
      #stamplist.push(day) if false == stamplist.has_key?(day)
      
      iter[:groups].each do |group_data|
        oper = group_data[:keys][0]
        datalist[oper] = {} if nil == datalist[oper]
        
        group_data[:metrics].each do |key,value|
          datalist[oper][day] = {key => value[:amount]}
          day_sum[day]-=value[:amount].to_f
        end
      end
      no_resource_data.push(day_sum[day])
    end

    chart_data=[stamplist]
    name_list = ["No Resource"]
    
    
    chart_data.push(no_resource_data)

    datalist.each_with_index  do |(key,value),index|
      data = []
      name_list.push(key)
      data[0] = key

      day_sum.each do |day,sum|
        if false == value.has_key?(day)
          data.push(0.0)
        else
          data.push(value[day]["AmortizedCost"].to_f)
        end
      end
      data.unshift()
      chart_data.push(data)
    end

    outObj = {
      :miqChart => :Column,
      :data =>
      {
        :x => 'x',
        #:xFormat => "%Y-%m-%d",
        :columns => chart_data,
        :empty =>
        {
          :label =>
          {
            :text => "No data available.",
          },
        },
        :groups => [
          name_list,
        ],
      },
      :axis =>
      {
        :x =>
        {
          #:categories =>stamplist,
          :tick =>
          {
            :culling=> {
              :max=> 14,
            },
            #:count => 14,
            #:fit => false,
            :multiline => false,
          }
        },
        :y =>
        {
          :label=>
          {
            :text =>"비용 ($)", 
            :position => "outer-top",
          },
          padding: {top: 200, bottom: 100}
        },
      },
      :tooltip =>
      {
        # :format =>
        # {
        #   :value => 'function (value, ratio, id) { return value.to_float.round(2)',
        # },
      },
      :miq =>
      {
        #:name_table =>name_table,
        #:categories =>stamplist,
        :expend_tooltip => true,
      },
      :legend => {},
    }
    #logger.debug("ssk_test_outObj = #{outObj.to_json}")
    return outObj
  end
  helper_method :aws_data_to_graph

###############################################################################
  def get_aws_cost_and_usage_data_per_instance
    vm_id = @record.id
    vm = find_record_with_rbac(VmCloud, vm_id)

    if @res != nil && @res_resources != nil
      return @res,@res_resources
    end
    client = get_cost_explorer_client
    data = 
    {
      :time_period =>
      {
        :start => (DateTime.now.utc - 7*3600*24).strftime("%Y-%m-%d"),#"2020-11-01",# required
        :end => (DateTime.now.utc + 1*3600*24).strftime("%Y-%m-%d"),#"2020-11-12",# required
      },
      
      :granularity => "DAILY",
      :metrics => [:AmortizedCost], #, :BlendedCost, :NetAmortizedCost, :NetUnblendedCost, :NormalizedUsageAmount, :UnblendedCost, :UsageQuantity], # required
    }
    #logger.debug("data = #{data}")
    #@res = client.get_cost_and_usage(data)
    data[:filter] = 
    {
      :and => [
        {
          :dimensions => {
            :key => :SERVICE,
            :values => [
              "Amazon Elastic Compute Cloud - Compute",
            ],
          },
        },
        {
          :dimensions => {
            :key => :RESOURCE_ID, # required
            :values => [vm.name,], # required
            # :key => :SERVICE,
            # :values => [
            #   "Amazon Elastic Compute Cloud - Compute"
            # ],
          },
        },
      ],
    }
    data[:group_by] =
    [
      {
        :type => "DIMENSION",
        :key => "USAGE_TYPE",
      },
    ]
    #logger.debug("data = #{data.to_json}")
    @res_resources = client.get_cost_and_usage_with_resources(data)
    #logger.debug("@res_resources = #{@res_resources}")
    #@response = [cost_to_summary(res.results_by_time)]
    #return @response
    # @res = res
    # data[:next_token] = res.next_token
    # while res.metric_data_results[0].status_code == "PartialData"
    #   res = client.get_metric_data(data)
    #   @res.metric_data_results[0][:timestamps].concat(res.metric_data_results[0][:timestamps])
    #   @res.metric_data_results[0][:values].concat(res.metric_data_results[0][:values])
    #   data[:next_token] = res.next_token
    # end
    #logger.debug("res = #{@res} ")
    logger.debug("res_resources = #{@res_resources}")
    return @res_resources
  end

  def aws_data_to_graph_per_instance

    res_resources=get_aws_cost_and_usage_data_per_instance
    #obj=res[:results_by_time]
    obj_res= res_resources[:results_by_time]
    index = 1
    datalist={}
    stamplist=['x']
    outObj = {}
    day_set = Set.new()


    obj_res.each do |iter|
      day = iter[:time_period][:start][0..9]
      day_set.add(day)
      stamplist.push(day)
      iter[:groups].each do |group_data|
        oper = group_data[:keys][0]
        datalist[oper] = {} if nil == datalist[oper]
        
        group_data[:metrics].each do |key,value|
          datalist[oper][day] = {key => value[:amount]}
        end
      end
    end

    chart_data=[stamplist]
    name_list = ["No Resource"]
    data=["No Resource"]
    # obj.each do |day|
    #   data.push(day[:total]["AmortizedCost"][:amount].to_f)
    # end
    chart_data.push(data)
    datalist.each_with_index  do |(key,value),index|
      data = []
      name_list.push(key)
      data[0] = key

      day_set.each do |day|
        if false == value.has_key?(day)
          data.push(0.0)
        else
          data.push(value[day]["AmortizedCost"].to_f)
        end
      end
      chart_data.push(data)
    end

    outObj = {
      :miqChart => :Column,
      :data =>
      {
        :x => 'x',
        #:xFormat => "%Y-%m-%d",
        :columns => chart_data,
        :empty =>
        {
          :label =>
          {
            :text => "No data available.",
          },
        },
      },
      :axis =>
      {
        :x =>
        {
          :tick =>
          {
            :culling=> {
              :max=> 14,
            },
            :multiline => false,
          }
        },
        :y =>
        {
          padding: {top: 200, bottom: 100}
        },
      },
      :miq =>
      {
        :expend_tooltip => true,
      },
      :legend => {},
    }
    #logger.debug("ssk_test_outObj = #{outObj.to_json}")
    return outObj
  end
  helper_method :aws_data_to_graph_per_instance
  
  def textual_group_aws_per_instance
    res_resources = get_aws_cost_and_usage_data_per_instance
    #logger.debug("res_resources = #{res_resources}")
    @response = aws_per_instance_data_to_summary(res_resources[:results_by_time])
    return @response
  end
  helper_method :textual_group_aws_per_instance

  def aws_per_instance_data_to_summary(obj_res)
    #logger.debug("obj = #{obj.to_json}")
    logger.debug("obj_res = #{obj_res.to_json}")
    reobj=[]
    sum_of_sum = 0
    # obj.each do |day|
    #   sum_list[day[:time_period][:start]] = day[:total]["AmortizedCost"][:amount].to_f# + " " + (day[:total]["AmortizedCost"].unit == "N / A" ? "" : day[:total]["AmortizedCost"].unit)
    #   sum_of_sum+= sum_list[day[:time_period][:start]].to_f
    # end

    obj_res.each do |iter|
      day = iter[:time_period][:start][0..9]
      sum = 0
      datalist = []
      iter.groups.each do |grouped|
        grouped[:keys].each_with_index do |key,index|
          grouped[:keys][index] = key + ' ($)'
        end
        val = grouped[:metrics]["AmortizedCost"].amount.to_f
        sum += val
        # if nil == resources_sum[grouped[:keys]]
        #   resources_sum[grouped[:keys]] = 
        #   {
        #     :label => grouped[:keys],
        #     :value =>0,
        #     :hoverClass => "no-hover",
        #   } 
        # end
        # resources_sum[grouped[:keys]][:value]+=val
        # resources_sum[grouped[:keys]][:value]=resources_sum[grouped[:keys]][:value].round(2)
        grouped_data = 
          {
            :label => grouped[:keys],
            :value => val.round(2),#grouped[:metrics]["AmortizedCost"].amount + " " + (grouped[:metrics]["AmortizedCost"].unit == "N / A" ? "" : grouped[:metrics]["AmortizedCost"].unit),
            :hoverClass => "no-hover",
          }
        datalist.push(grouped_data)
      end
      datalist.push(
        {
          :label => ["Sum ($)"],
          :value => sum.round(2),
          :hoverClass => "no-hover",
        })
      #sum
      # sum_data = 
      # {
      #   :label => "Sum ($)",
      #   :value => sum_list[day].round(2),#grouped[:metrics]["AmortizedCost"].amount + " " + (grouped[:metrics]["AmortizedCost"].unit == "N / A" ? "" : grouped[:metrics]["AmortizedCost"].unit),
      #   :hoverClass => "no-hover",
      # }
      # datalist.push(sum_data)
      dayData = 
      {
        :title => iter.time_period.start,
        :component => :GenericGroup,
        :items =>datalist,
      }
      reobj.push([dayData])
      
      
      
    end
    sum_items={}
    #sum_items.merge!(resources_sum)
    sum_items["Sum"] = 
      {
        :label => "Sum ($)",
        :value =>sum_of_sum.round(2),
        :hoverClass => "no-hover",
      } 

    sum_data = 
    {
      :title => "Sum",
      :component => :GenericGroup,
      :items =>sum_items.values,
    }
    reobj.push([sum_data])


    #logger.debug("reobj = #{reobj.to_json}")
    return reobj
  end
  ############################################################################

  def aws_data_to_summary(obj,obj_res)
    #logger.debug("obj = #{obj.to_json}")
    #logger.debug("obj_res = #{obj_res.to_json}")
    reobj=[]
    sum_list={}
    resources_sum = {}
    
    sum_of_sum = 0
    obj.each do |day|
      sum_list[day[:time_period][:start]] = day[:total]["AmortizedCost"][:amount].to_f# + " " + (day[:total]["AmortizedCost"].unit == "N / A" ? "" : day[:total]["AmortizedCost"].unit)
      sum_of_sum+= sum_list[day[:time_period][:start]].to_f
    end

    sum_of_no_resource=0
    obj_res.each do |iter|
      day = iter[:time_period][:start][0..9]
      sum = sum_list[day]
      datalist = []
      iter.groups.each do |grouped|
        grouped[:keys].each_with_index do |key,index|
          grouped[:keys][index] = key + ' ($)'
        end
        val = grouped[:metrics]["AmortizedCost"].amount.to_f
        sum -= val
        if nil == resources_sum[grouped[:keys]]
          resources_sum[grouped[:keys]] = 
          {
            :label => grouped[:keys],
            :value =>0,
            :hoverClass => "no-hover",
          } 
        end
        resources_sum[grouped[:keys]][:value]+=val
        resources_sum[grouped[:keys]][:value]=resources_sum[grouped[:keys]][:value].round(2)
        grouped_data = 
          {
            :label => grouped[:keys],
            :value => val.round(2),#grouped[:metrics]["AmortizedCost"].amount + " " + (grouped[:metrics]["AmortizedCost"].unit == "N / A" ? "" : grouped[:metrics]["AmortizedCost"].unit),
            :hoverClass => "no-hover",
          }
        datalist.push(grouped_data)
      end
      datalist.unshift(
        {
          :label => ["No Resource ($)"],
          :value => sum.round(2),
          :hoverClass => "no-hover",
        })
      sum_of_no_resource+=sum
      #sum
      sum_data = 
      {
        :label => "Sum ($)",
        :value => sum_list[day].round(2),#grouped[:metrics]["AmortizedCost"].amount + " " + (grouped[:metrics]["AmortizedCost"].unit == "N / A" ? "" : grouped[:metrics]["AmortizedCost"].unit),
        :hoverClass => "no-hover",
      }
      datalist.push(sum_data)
      dayData = 
      {
        :title => iter.time_period.start,
        :component => :GenericGroup,
        :items =>datalist,
      }
      reobj.push([dayData])
      
      
      
    end
    sum_items={}
    sum_items["No Resource"] = 
      {
        :label => "No Resource ($)",
        :value =>sum_of_no_resource.round(2),
        :hoverClass => "no-hover",
      } ;
    sum_items.merge!(resources_sum)
    sum_items["Sum"] = 
      {
        :label => "Sum ($)",
        :value =>sum_of_sum.round(2),
        :hoverClass => "no-hover",
      } 

    sum_data = 
    {
      :title => "Sum",
      :component => :GenericGroup,
      :items =>sum_items.values,
    }
    reobj.push([sum_data])


    #logger.debug("reobj = #{reobj.to_json}")
    return reobj
  end
  
  def get_aws_forecast_data
    return @res_fore if @res_fore != nil
    client = get_cost_explorer_client()
    data = 
    {
      :granularity => :DAILY,
      :metric => :AMORTIZED_COST,
      :time_period => {
        :start => (DateTime.now.utc + 24*3600).strftime("%Y-%m-%d"),#"2020-11-11",
        :end => (DateTime.now.utc + 24*3600*2).strftime("%Y-%m-%d"),#"2020-11-13",
      }
    }
    res = client.get_cost_forecast(data)
    @res_fore = res
    data[:next_token] = res.next_token
    while res.metric_data_results[0].status_code == "PartialData"
      res = client.get_cost_forecast(data)
      @res_fore.metric_data_results[0][:timestamps].concat(res.metric_data_results[0][:timestamps])
      @res_fore.metric_data_results[0][:values].concat(res.metric_data_results[0][:values])
      data[:next_token] = res.next_token
    end
    return @res_fore
  end

  def textual_group_aws_forecast
    @response_forecast = aws_data_to_summary(get_aws_forecast_data.metric_data_results)
    #logger.debug("response_forecast = #{@response_forecast}")
    return @response_forecast
  end
  helper_method :textual_group_aws_forecast

  def aws_forecast_data_to_graph
    res=get_aws_forecast_data
    obj=res[:results_by_time]
    obj_res= res_resources[:results_by_time]
    index = 1
    datalist={}
    stamplist=['x']
    outObj = {}
    day_set = Set.new()


    obj_res.each do |iter|
      day = iter[:time_period][:start][0..9]
      day_set.add(day)
      stamplist.push(day)
      iter[:groups].each do |group_data|
        oper = group_data[:keys][0]
        datalist[oper] = {} if nil == datalist[oper]
        
        group_data[:metrics].each do |key,value|
          datalist[oper][day] = {key => value[:amount]}
        end
      end
    end

    chart_data=[stamplist]
    name_list = ["No Resource"]
    data=["No Resource"]
    obj.each do |day|
      data.push(day[:total]["AmortizedCost"][:amount].to_f)
    end
    chart_data.push(data)
    datalist.each_with_index  do |(key,value),index|
      data = []
      name_list.push(key)
      data[0] = key

      day_set.each do |day|
        if false == value.has_key?(day)
          data.push(0.0)
        else
          data.push(value[day]["AmortizedCost"].to_f)
        end
      end
      chart_data.push(data)
    end

    outObj = {
      :miqChart => :Column,
      :data =>
      {
        :x => 'x',
        :xFormat => "%Y-%m-%d",
        :columns => chart_data,
        :empty =>
        {
          :label =>
          {
            :text => "No data available.",
          },
        },
        :groups => [
          name_list,
        ],
      },
      :axis =>
      {
        :x =>
        {
          #:categories =>stamplist,
          :tick =>
          {
            :count => 14,
            :fit => false,
            :multiline => false,
          }
        },
        :y =>
        {
          padding: {top: 200, bottom: 100}
        },
      },
      :miq =>
      {
        #:name_table =>name_table,
        #:categories =>stamplist,
        :expend_tooltip => true,
      },
      :legend => {},
    }
    #logger.debug("ssk_test_outObj = #{outObj.to_json}")
    return outObj
  end
  helper_method :aws_forecast_data_to_graph

  #####################################################################

  def get_aws_reservation_data
    return @res_reservation if @res_reservation != nil
    client = get_cost_explorer_client()
    data = 
    {
      :granularity => :DAILY,
      :time_period => {
        :start => "2020-11-02",#DateTime.now.utc - 3600 * 4,
        :end => "2020-11-20",#DateTime.now.utc,
      }
    }
    res = client.get_reservation_utilization(data)
    logger.debug("get_reservation_utilization = #{res}")
    @res_reservation = res
    if nil != res.next_page_token
      data[:next_page_token] = res.next_page_token
      while res.metric_data_results[0].status_code == "PartialData"
        res = client.get_reservation_utilization(data)
        @res_reservation.metric_data_results[0][:timestamps].concat(res.metric_data_results[0][:timestamps])
        @res_reservation.metric_data_results[0][:values].concat(res.metric_data_results[0][:values])
        data[:next_page_token] = res.next_page_token
      end
    end
    return @res_reservation
  end

  def textual_group_aws_reservation
    @response_reservation = aws_data_to_summary(get_aws_reservation_data.metric_data_results)
    logger.debug("response_reservation = #{@response_reservation}")
    return @response_reservation
  end
  helper_method :textual_group_aws_reservation
  
  def aws_reservation_data_to_graph
    res=get_aws_forecast_data
    obj=res[:results_by_time]
    obj_res= res_resources[:results_by_time]
    index = 1
    datalist={}
    stamplist=['x']
    outObj = {}
    day_set = Set.new()


    obj_res.each do |iter|
      day = iter[:time_period][:start][0..9]
      day_set.add(day)
      stamplist.push(day)
      iter[:groups].each do |group_data|
        oper = group_data[:keys][0]
        datalist[oper] = {} if nil == datalist[oper]
        
        group_data[:metrics].each do |key,value|
          datalist[oper][day] = {key => value[:amount]}
        end
      end
    end

    chart_data=[stamplist]
    name_list = ["No Resource"]
    data=["No Resource"]
    obj.each do |day|
      data.push(day[:total]["AmortizedCost"][:amount].to_f)
    end
    chart_data.push(data)
    datalist.each_with_index  do |(key,value),index|
      data = []
      name_list.push(key)
      data[0] = key

      day_set.each do |day|
        if false == value.has_key?(day)
          data.push(0.0)
        else
          data.push(value[day]["AmortizedCost"].to_f)
        end
      end
      chart_data.push(data)
    end

    outObj = {
      :miqChart => :Column,
      :data =>
      {
        :x => 'x',
        :xFormat => "%Y-%m-%d",
        :columns => chart_data,
        :empty =>
        {
          :label =>
          {
            :text => "No data available.",
          },
        },
        :groups => [
          name_list,
        ],
      },
      :axis =>
      {
        :x =>
        {
          #:categories =>stamplist,
          :tick =>
          {
            :count => 14,
            :fit => false,
            :multiline => false,
          }
        },
        :y =>
        {
          padding: {top: 200, bottom: 100}
        },
      },
      :miq =>
      {
        #:name_table =>name_table,
        #:categories =>stamplist,
        :expend_tooltip => true,
      },
      :legend => {},
    }
    #logger.debug("ssk_test_outObj = #{outObj.to_json}")
    return outObj
  end
  helper_method :aws_reservation_data_to_graph


  ##############################################################

  def features
    [
      {
        :role  => "instances_accord",
        :name  => :instances,
        :title => _("Instances by Provider")
      },
      {
        :role  => "images_accord",
        :name  => :images,
        :title => _("Images by Provider")
      },
      {
        :role  => "instances_filter_accord",
        :name  => :instances_filter,
        :title => _("Instances")
      },
      {
        :role  => "images_filter_accord",
        :name  => :images_filter,
        :title => _("Images")
      }
    ].map { |hsh| ApplicationController::Feature.new_with_hash(hsh) }
  end

  # redefine get_filters from VmShow
  def get_filters
    session[:instances_filters]
  end

  def prefix_by_nodetype(nodetype)
    case TreeBuilder.get_model_for_prefix(nodetype).underscore
    when "miq_template" then "images"
    when "vm"           then "instances"
    end
  end

  def set_elements_and_redirect_unauthorized_user
    logger.debug("set_elements_and_redirect_unauthorized_user")
    @nodetype, _id = parse_nodetype_and_id(params[:id])
    prefix = prefix_by_nodetype(@nodetype)

    # Position in tree that matches selected record
    if role_allows?(:feature => "instances_accord") && prefix == "instances"
      set_active_elements_authorized_user('instances_tree', 'instances')
    elsif role_allows?(:feature => "images_accord") && prefix == "images"
      set_active_elements_authorized_user('images_tree', 'images')
    elsif role_allows?(:feature => "#{prefix}_filter_accord")
      set_active_elements_authorized_user("#{prefix}_filter_tree", "#{prefix}_filter")
    else
      if (prefix == "vms" && role_allows?(:feature => "vms_instances_filter_accord")) ||
         (prefix == "templates" && role_allows?(:feature => "templates_images_filter_accord"))
        redirect_to(:controller => 'vm_or_template', :action => "explorer", :id => params[:id])
      else
        redirect_to(:controller => 'dashboard', :action => "auth_error")
      end
      return true
    end

    resolve_node_info(params[:id])
  end

  def tagging_explorer_controller?
    @explorer
  end

  # def skip_breadcrumb?
  #   breadcrumb_prohibited_for_action?
  # end

  #override in vm_common
  def replace_right_cell(options = {})
  logger.debug("replace_right_cell(#{options.to_json})")
    action, presenter, refresh_breadcrumbs = options.values_at(:action, :presenter, :refresh_breadcrumbs)
    refresh_breadcrumbs = true unless options.key?(:refresh_breadcrumbs)

    @explorer = true
    @sb[:action] = action unless action.nil?
    if @sb[:action] || params[:display]
      partial, action, @right_cell_text, options_from_right_cell = set_right_cell_vars(options) # Set partial name, action and cell header
    end

    if !@in_a_form && !@sb[:action]
      id = @record.present? ? TreeBuilder.build_node_id(@record) : x_node
      id = @sb[@sb[:active_accord]] if @sb[@sb[:active_accord]].present? && params[:action] != 'tree_select'
      get_node_info(id)
      type, _id = parse_nodetype_and_id(id)
      # set @delete_node since we don't rebuild vm tree
      @delete_node = params[:id] if @replace_trees  # get_node_info might set this

      record_showing = type && %w[Vm MiqTemplate].include?(TreeBuilder.get_model_for_prefix(type))
      c_tb = build_toolbar(center_toolbar_filename) # Use vm or template tb
      if record_showing
        cb_tb = build_toolbar(Mixins::CustomButtons::Result.new(:single))
        v_tb = build_toolbar("x_summary_view_tb")
      else
        cb_tb = build_toolbar(Mixins::CustomButtons::Result.new(:list))
        v_tb = build_toolbar("download_view_tb")
      end
    elsif %w[compare drift].include?(@sb[:action])
      @in_a_form = true # Turn on Cancel button
      c_tb = build_toolbar("#{@sb[:action]}_center_tb")
      v_tb = build_toolbar("#{@sb[:action]}_view_tb")
    elsif @sb[:action] == "performance"
      c_tb = build_toolbar("x_vm_performance_tb")
    elsif @sb[:action] == "drift_history"
      c_tb = build_toolbar("drifts_center_tb") # Use vm or template tb
    elsif @sb[:action] == 'snapshot_info'
      c_tb = build_toolbar("x_vm_snapshot_center_tb")
    elsif @sb[:action] == 'right_size'
      v_tb = build_toolbar("right_size_view_tb")
    elsif @sb[:action] == 'vmtree_info'
      c_tb = build_toolbar("x_vm_vmtree_center_tb")
    end

    # Build presenter to render the JS command for the tree update
    presenter ||= ExplorerPresenter.new(
      :active_tree => x_active_tree,
      :delete_node => @delete_node # Remove a new node from the tree
    )

    presenter.show(:default_left_cell).hide(:custom_left_cell)

    add_ajax = false
    if record_showing
      presenter.hide(:form_buttons_div)
      if @is_per_instance
        presenter.update(:main_div, r[:partial => "right_per_instance"])
      else
        presenter.update(:main_div, r[:partial => "right"])
      end
    elsif @in_a_form
      partial_locals = {:controller => 'vm'}
      partial_locals[:action_url] = @lastaction if partial == 'layouts/x_gtl'
      partial_locals.merge!(options_from_right_cell)
      presenter.update(:main_div, r[:partial => partial, :locals => partial_locals])

      locals = {:action_url => action, :record_id => @record.try(:id)}
      if %w[clone migrate miq_request_new pre_prov publish add_security_group remove_security_group
            reconfigure resize live_migrate attach detach evacuate
            associate_floating_ip disassociate_floating_ip].include?(@sb[:action])
        locals[:no_reset]        = true                              # don't need reset button on the screen
        locals[:submit_button]   = @sb[:action] != 'miq_request_new' # need submit button on the screen
        locals[:continue_button] = @sb[:action] == 'miq_request_new' # need continue button on the screen
        update_buttons(locals) if @edit && @edit[:buttons].present?
      end

      if ['snapshot_add'].include?(@sb[:action])
        locals[:no_reset]      = true
        locals[:create_button] = true
      end

      locals[:action_url] = nil if ['chargeback'].include?(@sb[:action])

      if %w[ownership protect reconfigure retire tag].include?(@sb[:action])
        locals[:multi_record] = true # need save/cancel buttons on edit screen even tho @record.id is not there
        locals[:record_id]    = @sb[:rec_id] || @edit[:object_ids][0] if @sb[:action] == "tag"
        unless %w[ownership retire].include?(@sb[:action])
          presenter[:build_calendar] = {
            :date_from => Time.zone.now,
            :date_to   => nil,
          }
        end
      end

      add_ajax = true

      if %w[compare drift].include?(@sb[:action])
        presenter.update(:custom_left_cell, r[
          :partial => 'layouts/listnav/x_compare_sections', :locals => {:truncate_length => 23}])
        presenter.show(:custom_left_cell).hide(:default_left_cell)
      end
    elsif @sb[:action] || params[:display]
      partial_locals = { :controller => 'vm' }
      if partial == 'layouts/x_gtl'
        partial_locals[:action_url] = @lastaction

        # Set parent record id & class for JS function miqGridSort to build URL
        presenter[:parent_id]    = @record.id
        presenter[:parent_class] = params[:controller]
      end
      presenter.update(:main_div, r[:partial => partial, :locals => partial_locals])

      add_ajax = true
      presenter[:build_calendar] = true
    else
      presenter.update(:main_div, r[:partial => 'layouts/x_gtl'])
    end

    if add_ajax && %w[performance timeline].include?(@sb[:action])
      presenter[:ajax_action] = {
        :controller => request.parameters["controller"],
        :action     => @ajax_action,
        :record_id  => @record.id
      }
    end

    replace_search_box(presenter, :nameonly => %i[images_tree instances_tree vandt_tree].include?(x_active_tree))

    if @sb[:action] == "policy_sim"
      presenter[:clear_tree_cookies] = "edit_treeOpenStatex"
      presenter[:tree_expand_all] = false
    end

    # Handle bottom cell
    if @pages || @in_a_form
      if @pages && !@in_a_form
        presenter.hide(:form_buttons_div)
      elsif @in_a_form
        # these subviews use angular, so they need to use a special partial
        # so the form buttons on the outer frame can be updated.
        if @sb[:action] == 'dialog_provision'
          if show_old_dialog_submit_and_cancel_buttons?(params)
            presenter.update(:form_buttons_div, r[
              :partial => 'layouts/x_dialog_buttons',
              :locals  => {
                :action_url => action,
                :record_id  => @edit[:rec_id],
              }
            ])
          else
            presenter.update(:form_buttons_div, '')
            presenter.remove_paging.hide(:form_buttons_div)
          end
        elsif %w[chargeback reconfigure_update retire].exclude?(action) && !hide_x_edit_buttons(action)
          presenter.update(:form_buttons_div, r[:partial => 'layouts/x_edit_buttons', :locals => locals])
        end

        if %w[pre_prov].include?(action)
          presenter.update(:pre_prov_form_buttons_div, r[:partial => 'layouts/x_edit_buttons', :locals => locals])
        end

        # Make sure the form_buttons_div is empty.
        # it would remain on the screen if prior to retire some action that uses the form_buttons_div was used
        # such as "edit tags" or "manage policies".
        presenter.update(:form_buttons_div, '') if action == "retire" || hide_x_edit_buttons(action)

        presenter.remove_paging.show(:form_buttons_div)

        # evm_relationship_update uses React form and buttons
        presenter.hide(:form_buttons_div) if action == "evm_relationship_update"
      end

      if %w[add_security_group associate_floating_ip attach detach disassociate_floating_ip evacuate live_migrate ownership remove_security_group resize].include?(@sb[:action])
        presenter.hide(:form_buttons_div, :paging_div)
      else
        presenter.show(:paging_div)
      end
    else
      presenter.hide(:paging_div)
    end

    presenter[:right_cell_text] = @right_cell_text

    presenter.reload_toolbars(:center => c_tb, :custom => cb_tb, :view => v_tb)

    presenter.set_visibility(c_tb.present? || v_tb.present?, :toolbar)

    presenter[:record_id] = @record.try(:id)

    # Hide/show searchbox depending on if a list is showing
    presenter.set_visibility(!(@record || @in_a_form), :adv_searchbox_div)
    presenter[:clear_search_toggle] = clear_search_status

    presenter[:osf_node] = x_node # Open, select, and focus on this node

    presenter.hide(:blocker_div) unless @edit && @edit[:adv_search_open]
    presenter[:hide_modal] = true
    presenter[:lock_sidebar] = @in_a_form && @edit

    presenter.update(:breadcrumbs, r[:partial => 'layouts/breadcrumbs']) if refresh_breadcrumbs

    render :json => presenter.for_render
  end


  menu_section :cost
  has_custom_buttons
end