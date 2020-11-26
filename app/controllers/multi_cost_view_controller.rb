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
        return @res if @res!= nil
        clients = get_all_aws_clients
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

        @res=[]
        clients.each_with_index do |client,index|
            res = client.get_cost_and_usage(data)
            @res.push(res)
            
        end
        return @res
    end

    def aws_data_to_graph
        #res,res_resources=get_aws_cost_and_usage_data
        res_list = get_aws_datas
        chart_data=[]
        
        inserted_x=false
        res_list.each_with_index do |res,index|
            obj=res[:results_by_time]
            
            datalist={}
            stamplist=['x']
            outObj = {}
            day_sum = {}
            no_resource_data=[@model.all[index][:name]]

            obj.each do |day|
                no_resource_data.push(day[:total]["AmortizedCost"][:amount].to_f.round(2))
                stamplist.push(day[:time_period][:start]) if false == inserted_x
            end
            if false == inserted_x
                chart_data.push(stamplist)
                inserted_x=true
            end
            chart_data.push(no_resource_data)
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
        return outObj
    end
    helper_method :aws_data_to_graph



    def textual_group_aws
        res_list = get_aws_datas
        return aws_data_to_summary(res_list)
    end
    helper_method :textual_group_aws

    def aws_data_to_summary(res_list)
        reobj=[]
        
        res_list[0][:results_by_time].size.times do |index|
            resobj=
            {
                :title => res_list[0][:results_by_time][index][:time_period][:start],
                :component => :GenericGroup,
            }
            items=[]
            res_list.each_with_index do |res,res_index|
                item = 
                {
                    :label => [@model.all[res_index][:name] + " ($)"],
                    :value => res[:results_by_time][index][:total]["AmortizedCost"][:amount].to_f.round(2),
                    :hoverClass => "no-hover",
                }
                items.push(item)
            end
            resobj[:items]=items

            reobj.push([resobj])    
        end
    
        logger.debug("reobj = #{reobj.to_json}")
        return reobj
    end

end