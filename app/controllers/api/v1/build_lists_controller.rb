# -*- encoding : utf-8 -*-
class Api::V1::BuildListsController < Api::V1::BaseController
  before_filter :authenticate_user!
  skip_before_filter :authenticate_user!, :only => [:show, :index] if APP_CONFIG['anonymous_access']

  load_and_authorize_resource :project, :only => :index
  load_and_authorize_resource :build_list, :only => [:create, :cancel, :publish, :reject_publish]#, :shallow => true

  def index
    filter = BuildList::Filter.new(nil, current_user, params[:filter] || {})
    @build_lists = filter.find.scoped(:include => [:save_to_platform, :project, :user, :arch])
    @build_lists = @build_lists.recent.paginate :page => params[:page], :per_page => params[:per_page]
  end

  def create
    notices, errors = [], []
    json_report = {:build_lists => []}
    project = Project.find(params[:build_list][:project_id])
    platform = Platform.find params[:build_list][:save_to_platform_id]
    params[:build_list][:auto_publish] = false if platform.released

    Arch.where(:id => params[:arches]).each do |arch|
      Platform.main.where(:id => params[:build_for_platforms]).each do |build_for_platform|
        build_list = project.build_lists.build(params[:build_list])
        build_list.commit_hash = project.repo.commits(build_list.project_version.match(/^latest_(.+)/).to_a.last ||
                                  build_list.project_version).first.id if build_list.project_version
        build_list.build_for_platform = build_for_platform; build_list.arch = arch; build_list.user = current_user
        build_list.include_repos = build_list.include_repos.select {|ir| build_list.build_for_platform.repository_ids.include? ir.to_i}
        build_list.priority = current_user.build_priority # User builds more priority than mass rebuild with zero priority
        flash_options = {:project_version => build_list.project_version, :arch => arch.name, :build_for_platform => build_for_platform.name}
        if build_list.save
          msg = t("flash.build_list.saved", flash_options)
          notices << msg
        else
          msg = t("flash.build_list.save_error", flash_options)
          errors << msg
        end
        json_report[:build_lists] << {"id" => build_list.id, "message" => msg}
      end
    end

    errors << t("flash.build_list.no_arch_or_platform_selected") if errors.blank? and notices.blank?
    render :json => json_report.to_json
  end

  def cancel
    if @build_list.cancel
      render :json => {:is_canceled => true, :url => api_v1_build_list_path(@build_list, :format => :json), :message => t('layout.build_lists.cancel_success')}
    else
      render :json => {:is_canceled => false, :url => api_v1_build_list_path(@build_list, :format => :json), :message => t('layout.build_lists.cancel_fail')}
    end
  end

  def publish
    if @build_list.publish
      render :json => {:is_published => true, :url => api_v1_build_list_path(@build_list, :format => :json), :message => t('layout.build_lists.publish_success')}
    else
      render :json => {:is_published => false, :url => api_v1_build_list_path(@build_list, :format => :json), :message => t('layout.build_lists.publish_fail')}
    end
  end

  def reject_publish
    if @build_list.reject_publish
      render :json => {:is_reject_published => true, :url => api_v1_build_list_path(@build_list, :format => :json), :message => t('layout.build_lists.reject_publish_success')}
    else
      render :json => {:is_reject_published => true, :url => api_v1_build_list_path(@build_list, :format => :json), :message => t('layout.build_lists.reject_publish_fail')}
    end
  end

end
