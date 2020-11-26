require 'miq_bulk_import'
class TestDummyPageController < ApplicationController
  include StartUrl
  include Mixins::GenericSessionMixin
  include Mixins::BreadcrumbsMixin

  before_action :check_privileges
  before_action :get_session_data
  after_action :cleanup_action
  after_action :set_session_data

  def self.model
    ManageIQ::Providers::CloudManager
  end

  def self.table_name
    @table_name ||= "ems_cloud"
  end
  
  def index
    #remove listnav
    #application_helper/page_layouts.rb => add to layout_uses_listnav?
    @layout = 'test_dummy_page'
    @breadcrumbs = []
    model = self.class.model
    #logger.debug("model = #{model}")
    #record = identify_record(2, EmsCloud)
    #logger.debug("record = #{record}")
    #vm = find_record_with_rbac(VmCloud,2)
    #logger.debug("VmCloud = #{VmCloud}")
    #logger.debug("ExtManagementSystem=#{ExtManagementSystem}")
    
  end

  def test
    logger.debug("@date1=#{@date1}")
    logger.debug("params = #{params.to_json}")
  end

  menu_section :dummy
end