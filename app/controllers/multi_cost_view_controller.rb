class MultiCostViewController < ApplicationController
    include StartUrl
    include Mixins::GenericSessionMixin
    include Mixins::BreadcrumbsMixin
  
    # before_action :check_privileges
    # before_action :get_session_data
    # after_action :cleanup_action
    # after_action :set_session_data
    def self.model
        return ManageIQ::Providers::Amazon::CloudManager
    end

    def index 
      @model = self.class.model
      @layout = 'test_dummy_page'
      logger.debug("self.class.model = #{@model.all.to_json}")

    end
    def get_all_aws_clients
        require "aws-sdk-ec2"
        require "aws-sdk-costexplorer"
        clients=[]
        ManageIQ::Providers::Amazon::CloudManager.all.each do |manager|
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
            client = Aws::CostExplorer::Client.new(options) 
            clients.push(client)
        end
        return clients
    end
    def get_aws_datas

        clients = get_all_aws_clients
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
        res=[]
        clients.each do |client|
            res.push(client.get_cost_and_usage(data))
        end
        # data[:filter] = 
        # {
        # :dimensions => {
        #     :key => :SERVICE,
        #     :values => [
        #     "Amazon Elastic Compute Cloud - Compute"
        #     ],
        # },
        # }
        # data[:group_by] =
        # [
        # {
        #     :type => "DIMENSION",
        #     :key => "RESOURCE_ID",
        # },
        # ]
        #@res_resources = client.get_cost_and_usage_with_resources(data)
        return res
    end

    def aws_data_to_graph
        #res,res_resources=get_aws_cost_and_usage_data
        res_list = get_aws_datas
        chart_data=[]
        #logger.debug("res_list =#{res_list}")
        inserted_x=false
        res_list.each_with_index do |res,index|
            obj=res[:results_by_time]
            index
            #obj_res= res_resources[:results_by_time]
            index = 1
            datalist={}
            stamplist=['x']
            outObj = {}
            day_sum = {}
            #logger.debug("res=#{res}")
            ##
            logger.debug ("@model.all[#{index}][:name]=#{@model.all[index-1][:name]}")
            no_resource_data=[@model.all[index-1][:name]]

            obj.each do |day|
                #day_sum[day[:time_period][:start]] = day[:total]["AmortizedCost"][:amount].to_f
                no_resource_data.push(day[:total]["AmortizedCost"][:amount].to_f)
                stamplist.push(day[:time_period][:start]) if false == inserted_x
            end
            if false == inserted_x
                chart_data.push(stamplist)
                inserted_x=true
            end
            ##
            
            #stamplist.push(day) if false == stamplist.has_key?(day)
            
            # iter[:groups].each do |group_data|
            #     oper = group_data[:keys][0]
            #     datalist[oper] = {} if nil == datalist[oper]
                
            #     group_data[:metrics].each do |key,value|
            #     datalist[oper][day] = {key => value[:amount]}
            #     day_sum[day]-=value[:amount].to_f
            #     end
            # end
            #no_resource_data.push(day_sum[day])
            # end
        
            # chart_data=[stamplist]
            # name_list = ["No Resource"]
            
            
            chart_data.push(no_resource_data)
        
            # datalist.each_with_index  do |(key,value),index|
            # data = []
            # name_list.push(key)
            # data[0] = key
        
            # day_sum.each do |day,sum|
            #     if false == value.has_key?(day)
            #     data.push(0.0)
            #     else
            #     data.push(value[day]["AmortizedCost"].to_f)
            #     end
            # end
            # data.unshift()
            # chart_data.push(data)
            # end
        end
    
        outObj = {
          :miqChart => :Line,
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
            # :groups => [
            #   name_list,
            # ],
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
        #   :tooltip =>
        #   {
        #     # :format =>
        #     # {
        #     #   :value => 'function (value, ratio, id) { return value.to_float.round(2)',
        #     # },
        #   },
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
end