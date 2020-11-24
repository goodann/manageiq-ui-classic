class CloudWatchController < ApplicationController
  
  include VmCommon # common methods for vm controllers
  include VmRemote # methods for VM remote access
  include VmShowMixin
  include Mixins::BreadcrumbsMixin


  before_action :check_privileges
  before_action :get_session_data
  after_action :cleanup_action
  after_action :set_session_data

  def get_data
    newParam={
      :model_name=>"ManageIQ_Providers_CloudManager",
      :model=>"ManageIQ_Providers_CloudManager",
      :active_tree=>"instances_tree",
      :explorer => true,
      :records => [5,8],
      :additional_options => {
        :named_scope=>nil,
        :gtl_dbname=>nil,
        :model=>"ManageIQ_Providers_CloudManager"
      }
    }
    #newParam[:model]="ManageIQ::Providers::CloudManager::Vm"
    options = process_params_options(newParam)
    logger.debug("report_data(params) = #{params.to_json}")
    logger.debug("report_data(options) = #{options.to_json}")
    #options[:model]="ManageIQ::Providers::CloudManager::Vm"
    model_view = process_params_model_view(params, options)
    
    #logger.debug("model_view=#{model_view}")
    @edit = session[:edit]
    @view, settings = get_view(model_view, options, true)
    settings = set_variables_report_data(settings, @view)
    #logger.debug("settings=#{settings}")
    #logger.debug("@view=#{@view.to_json}")
    if options && options[:named_scope] == "in_my_region" && options[:model] == "Tenant"
      @view.table = filter_parent_name_tenant(@view.table)
    end
    return view_to_hash(@view, true)
  end

  def index
    data = get_data
    #logger.debug("get_data=#{data.to_json}")
    if nil == params[:start_time]
      @start_time = (DateTime.now.utc - 7*3600*24)
      @end_time = DateTime.now.utc
    else
      @start_time = DateTime.parse(params[:start_time])
      @end_time = DateTime.parse(params[:end_time])
    end
    if nil == params[:period]
      @period = "3600"
    else
      @period = params[:period]
    end
    logger.debug("index params=#{params}")
    
    logger.debug("@start_time params=#{@start_time}")
    logger.debug("@end_time params=#{@end_time}")
    explorer
    #flash_to_session
    #redirect_to(:action => 'explorer')
  end

  def refind
    
    
    #logger.debug("refind params=#{params}")
    @start_time = params[:start_time]
    @end_time = params[:end_time]
    
    redirect_to(:action => 'index', :id => params[:id],:start_time => params[:start_time],:end_time => params[:end_time],:period=>params[:period])

  end

  # def show

  # end

  def attach
    logger.debug("find_record_with_rbac(VmCloud, params[:id])=#{params.to_json}")
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
    # [
    #     %i[properties] +
    #       (@record.kind_of?(VmCloud) ? %i[vm_cloud_relationships] : %i[template_cloud_relationships]) +
    #       %i[labels],
    #     %i[power_management]
    # ]
  end

  helper_method :textual_group_list

  def get_cloud_watch_client
    #if @client == nil
      require "aws-sdk-ec2"
      require "aws-sdk-cloudwatch"

      vm_id = @record.id
      vm = find_record_with_rbac(VmCloud, vm_id)

      ext_mgt_system = vm.ext_management_system
      userid = ext_mgt_system.authentication_userid
      passwd = ext_mgt_system.authentication_password
      region = ext_mgt_system.provider_region
      
      options = {
        :credentials   => Aws::Credentials.new(userid, passwd),
        :region        => region,#'ap-northeast-2',
        :logger        => $aws_log,
        :log_level     => :debug,
        :log_formatter => Aws::Log::Formatter.new(Aws::Log::Formatter.default.pattern.chomp),
      }
      @client = Aws::CloudWatch::Client.new(options) 
    #end
    return @client
  end
  
  @@metric_names = 
  {
    :CPUUtilization => {:label => "CPU Utilization Average", :unit => :Percent,},
    :DiskReadBytes => {:label => "Disk Read Bytes Average", :unit => :Bytes,},
    :DiskReadOps => {:label => "Disk Read Ops Average", :unit => :Count,},
    :DiskWriteBytes => {:label => "Disk Write Bytes Average", :unit => :Bytes,},
    :DiskWriteOps => {:label => "Disk Write Ops Average", :unit => :Count,},
    :NetworkIn => {:label => "Network In Average", :unit => :Bytes,},
    :NetworkOut => {:label => "Network Out Average", :unit => :Bytes,},
    :NetworkPacketsIn => {:label => "Network Packets In Average", :unit => :Count,},
    :NetworkPacketsOut => {:label => "Network Packets Out Average", :unit => :Count,},
    #:MetadataNoToken,
    :StatusCheckFailed => {:label => "Status Check Failed Sum", :unit => :Count,},
    :StatusCheckFailed_Instance => {:label => "Status Check Failed Instance Sum", :unit => :Count,},
    :StatusCheckFailed_System => {:label => "Status Check Failed System Sum", :unit => :Count,},
  }
  # @@stat_list = 
  # [
  #   :Average,:Average,:Average,
  #   :Average,:Average,:Average,
  #   :Average,:Average,:Average,
  #   :Average,:Average,:Average,
  #   :Average,
  # ]
  # @@unit_list = 
  # [
  #   :Percent ,:Count,:Count,
  #   :Bytes,:Bytes,
  #   :Bytes,:Bytes,
  #   #:Kilobytes,:Kilobytes,
  #   :Count,:Count,:Count,
  #   :Count,:Count,:Count,
  #   :Count,
  # ]
  def get_metric_names
    return @@metric_names
  end
  helper_method :get_metric_names
  def get_aws_metric_data
    
    if nil == @record
      attach
    end
    vm_id = @record.id
    vm = find_record_with_rbac(VmCloud, vm_id)
    client = get_cloud_watch_client()
   


    @res = {:metric_data_results => {}}
    if nil == params[:start_time]
      @start_time = (DateTime.now.utc - 7*3600*24)
      @end_time = DateTime.now.utc
    else
      @start_time = DateTime.parse(params[:start_time])
      @end_time = DateTime.parse(params[:end_time])
    end
    if nil == params[:period]
      @period = 3600 
    else
      @period = params[:period]
    end
    #logger.debug("vm = #{vm.to_json}")
    @@metric_names.each_with_index do |(metric,value),index|
      @res[:metric_data_results][metric]={}
      @res[:metric_data_results][metric][:timestamps]=[]
      @res[:metric_data_results][metric][:values]=[]
      data = 
      {
        :metric_data_queries => [ # required
          {
            :id => "m1", # required
            :metric_stat => {
              :metric => { # required
                :namespace => "AWS/EC2",
                :metric_name => metric,
                :dimensions => [
                  {
                    :name => "InstanceId", # required
                    :value => vm.uid_ems, # required
                  },
                ],
              },
              :period => @period, # required
              :stat => :Average, # required
              :unit => value[:unit], # accepts Seconds, Microseconds, Milliseconds, Bytes, Kilobytes, Megabytes, Gigabytes, Terabytes, Bits, Kilobits, Megabits, Gigabits, Terabits, Percent, Count, Bytes/Second, Kilobytes/Second, Megabytes/Second, Gigabytes/Second, Terabytes/Second, Bits/Second, Kilobits/Second, Megabits/Second, Gigabits/Second, Terabits/Second, Count/Second, None
            },
            :label => value[:label],
          },
          # {
          #   :id => "m2", # required
          #   :metric_stat => {
          #     :metric => { # required
          #       :namespace => "AWS/EC2",
          #       :metric_name => metric,
          #       :dimensions => [
          #         {
          #           :name => "InstanceId", # required
          #           :value => "i-07c7445f1ec2259f5",
          #         },
          #       ],
          #     },
          #     :period => @period, # required
          #     :stat => :Average,#@@stat_list[index], # required
          #     :unit => value[:unit], # accepts Seconds, Microseconds, Milliseconds, Bytes, Kilobytes, Megabytes, Gigabytes, Terabytes, Bits, Kilobits, Megabits, Gigabits, Terabits, Percent, Count, Bytes/Second, Kilobytes/Second, Megabytes/Second, Gigabytes/Second, Terabytes/Second, Bits/Second, Kilobits/Second, Megabits/Second, Gigabits/Second, Terabits/Second, Count/Second, None
          #   },
          #   #:label => metric,
          # },
        ],
        :start_time => @start_time.strftime("%Y-%m-%dT%H:%M:%S"),#"2020-10-28T00:00:00",#DateTime.now.utc - 3600 * 4,
        :end_time => @end_time.strftime("%Y-%m-%dT%H:%M:%S"),#"2020-11-10T05:00:00",#DateTime.now.utc,
        :scan_by => "TimestampAscending", # accepts TimestampDescending, TimestampAscending
        :max_datapoints => 1000,
      }
      #logger.debug("data = #{data}")
      res = client.get_metric_data(data)
      #logger.debug("res = #{res}")
      @res[:metric_data_results][metric][:timestamps].concat(res.metric_data_results[0][:timestamps])
      @res[:metric_data_results][metric][:values].concat(res.metric_data_results[0][:values])
      data[:next_token] = res.next_token
      while res.metric_data_results[0].status_code == "PartialData"
        res = client.get_metric_data(data)
        @res[:metric_data_results][metric][:timestamps].concat(res.metric_data_results[0][:timestamps])
        @res[:metric_data_results][metric][:values].concat(res.metric_data_results[0][:values])
        data[:next_token] = res.next_token
      end
    end
    return @res
  end

  def textual_group_aws
    @response = aws_data_to_summary(get_aws_metric_data[:metric_data_results])  
    return @response
  end
  helper_method :textual_group_aws
  
  def aws_data_to_graph(metric_index)
    
    if @outObj != nil
      return @outObj[metric_index] 
    end
    obj=get_aws_metric_data[:metric_data_results]
    index = 1
    datalist=[]
    stamplist=Set.new()
    @outObj = []
    
    timelist=Set.new(['x'])
    logger.debug("obj.to_json=#{obj.to_json}");
    obj.each_with_index do |(metric,data),index|
      datalist[index]=[metric]
      
      data[:timestamps].each do |val|
        stamplist.add(val.month.to_s + '-' + val.day.to_s + ' ' + val.hour.to_s + ':'+ val.min.to_s)
        timelist.add(val.strftime("%Y-%m-%d %H:%M:%S"))
      end
      data[:values].each do |val|
        datalist[index].push(val)
      end
      
      @outObj[index] = {
        size: {
          :width => 360,
        },
        :miqChart => :Line,
        :point =>
        {
          :show => false,
        },
        :data =>
        {
          :x => 'x',
          :xFormat => "%Y-%m-%d %H:%M:%S",
          :columns => 
          [
            timelist,
            datalist[index],
          ],
          # :names => 
          # {
          #   "data1" => namelist[index],
          # },
          :empty =>
          {
            :label =>
            {
              :text => "No data available.",
            },
          },
          #:labels => true,
        },
        :axis =>
        {
          :x =>
          {
            :type => :timeseries,
            :localtime => true,
            #:categories => stamplist,
            :multiline => false,
            :tick =>
            {
              :fit => true,
              :format => '%m/%d',#'%Y-%m-%d',
              :culling=> true,
              # :culling=> {
              #   :max=> 4,
              # },
            },
            :show => true,
          },
          :y =>
          {
            :show => true,
            :padding => {top: 200, bottom: 50},
            :label => 
            {
              :text => @@metric_names[metric][:unit],
              :position => "outer-top",
            },
          },
        },
        :tooltip =>
        {
          :format => '%Y-%m-%d %H:%M:%S',
        },
        :miq =>
        {
          # :name_table =>
          # {
          #   "data1" => namelist[index],
          # },
          #:categories =>stamplist,
          :expend_tooltip => true,
        },
        :legend => {
          :show => false,
          #:position => :bottom,
        },
      }
    end
    
    
  return @outObj[metric_index]
  end
  helper_method :aws_data_to_graph

  def aws_data_to_summary(obj)
    #logger.debug ("cost_to_summary(#{obj.to_json})")
    reobj=[]
    tableList=[]
    obj.each do |metric,value|
      datalist=[]
      
      value[:timestamps].each_with_index do |val, index|
        datalist.push({ 
          :label => val,
          :value => value[:values][index],
          :hoverClass => "no-hover",
        })
        
      end
      #logger.debug("datalist = #{datalist}")
      dayData = {
        :title => metric,
        :component => :GenericGroup,
        :items =>datalist,
      }
      tableList=[dayData]
      reobj.push(tableList)
    end
    
    return reobj
  end

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

  def skip_breadcrumb?
    breadcrumb_prohibited_for_action?
  end
  def test
    logger.debug("clicked test")
  end
  helper_method :test
  #override in vm_common
  def replace_right_cell(options = {})
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
        v_tb = build_toolbar("x_gtl_view_tb")
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
      #presenter.update(:main_div, r[:partial => "layouts/textual_groups_custom"])
      presenter.update(:main_div, r[:partial => "right"])
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

    presenter[:clear_gtl_list_grid] = @gtl_type && @gtl_type != 'list'
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
        elsif %w[attach detach live_migrate resize evacuate ownership add_security_group remove_security_group
                 associate_floating_ip disassociate_floating_ip].include?(@sb[:action])
          presenter.update(:form_buttons_div, r[:partial => "layouts/angular/paging_div_buttons"])
        elsif %w[chargeback reconfigure_update retire].exclude?(action) && !hide_x_edit_buttons(action)
          presenter.update(:form_buttons_div, r[:partial => 'layouts/x_edit_buttons', :locals => locals])
        end

        # Make sure the form_buttons_div is empty.
        # it would remain on the screen if prior to retire some action that uses the form_buttons_div was used
        # such as "edit tags" or "manage policies".
        presenter.update(:form_buttons_div, '') if action == "retire" || hide_x_edit_buttons(action)

        presenter.remove_paging.show(:form_buttons_div)

        # evm_relationship_update uses React form and buttons
        presenter.hide(:form_buttons_div) if action == "evm_relationship_update"
      end
      presenter.show(:paging_div)
    else
      presenter.hide(:paging_div)
    end

    presenter[:right_cell_text] = @right_cell_text

    presenter.reload_toolbars(:center => c_tb, :custom => cb_tb, :view => v_tb)

    presenter.set_visibility(c_tb.present? || v_tb.present?, :toolbar)

    presenter[:record_id] = @record.try(:id)

    # Hide/show searchbox depending on if a list is showing
    #presenter.set_visibility(!(@record || @in_a_form), :adv_searchbox_div)
    presenter[:clear_search_toggle] = clear_search_status

    presenter[:osf_node] = x_node # Open, select, and focus on this node

    presenter.hide(:blocker_div) unless @edit && @edit[:adv_search_open]
    presenter[:hide_modal] = true
    presenter[:lock_sidebar] = @in_a_form && @edit

    presenter.update(:breadcrumbs, r[:partial => 'layouts/breadcrumbs']) if refresh_breadcrumbs

    render :json => presenter.for_render
  end


  menu_section :watch
  has_custom_buttons
end