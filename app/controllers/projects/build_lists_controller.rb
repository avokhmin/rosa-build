class Projects::BuildListsController < Projects::BaseController
  include FileStoreHelper
  include BuildListsHelper

  NESTED_ACTIONS = [:index, :new, :create]

  before_filter :authenticate_user!
  skip_before_filter :authenticate_user!, only: [:show, :index, :log] if APP_CONFIG['anonymous_access']

  before_filter :find_build_list, only: [:show, :publish, :cancel, :update, :log, :create_container, :dependent_projects]

  load_and_authorize_resource :project, only: [:new, :create]
  load_resource :project, only: :index, parent: false
  load_and_authorize_resource :build_list, through: :project, only: NESTED_ACTIONS, shallow: true
  load_and_authorize_resource except: NESTED_ACTIONS

  before_filter :create_from_build_list, only: :new

  def index
    authorize!(:show, @project) if @project
    params[:filter].each{|k,v| params[:filter].delete(k) if v.blank? } if params[:filter]

    respond_to do |format|
      format.html
      format.json do
        @filter = BuildList::Filter.new(@project, current_user, current_ability, params[:filter] || {})
        params[:page] = params[:page].to_i == 0 ? nil : params[:page]
        params[:per_page] = if BuildList::Filter::PER_PAGE.include? params[:per_page].to_i
                              params[:per_page].to_i
                            else
                              BuildList::Filter::PER_PAGE.first
                            end
        @bls_count = @filter.find.count
        @bls = @filter.find.recent.paginate(page: params[:page], per_page: params[:per_page])
        @build_lists = BuildList.where(id: @bls.pluck(:id)).recent
                                .includes(:save_to_platform,
                                          :save_to_repository,
                                          :build_for_platform,
                                          :user,
                                          :source_packages,
                                          project: :project_statistics)

        @build_server_status = AbfWorkerStatusPresenter.new.projects_status
      end
    end
  end

  def new
    if params[:show] == 'inline' && params[:build_list_id].present?
      render json: new_build_list_data(@build_list, @project, params), layout: false
    else
      render :new
    end
  end

  def create
    notices, errors = [], []

    @repository = Repository.find params[:build_list][:save_to_repository_id]
    @platform = @repository.platform

    params[:build_list][:save_to_platform_id] = @platform.id

    build_for_platforms = Repository.select(:platform_id).
      where(id: params[:build_list][:include_repos]).group(:platform_id).map(&:platform_id)

    build_lists = []
    Arch.where(id: params[:arches]).each do |arch|
      Platform.main.where(id: build_for_platforms).each do |build_for_platform|
        @build_list = @project.build_lists.build(params[:build_list])
        @build_list.build_for_platform = build_for_platform; @build_list.arch = arch; @build_list.user = current_user
        @build_list.include_repos = @build_list.include_repos.select {|ir| @build_list.build_for_platform.repository_ids.include? ir.to_i}
        @build_list.priority = current_user.build_priority # User builds more priority than mass rebuild with zero priority

        flash_options = { project_version: @build_list.project_version, arch: arch.name, build_for_platform: build_for_platform.name }
        if authorize!(:create, @build_list) && @build_list.save
          build_lists << @build_list
          notices << t('flash.build_list.saved', flash_options)
        else
          errors << t('flash.build_list.save_error', flash_options)
        end
      end
    end
    errors << t('flash.build_list.no_arch_or_platform_selected') if errors.blank? and notices.blank?
    if errors.present?
      @build_list ||= BuildList.new
      flash[:error] = errors.join('<br>').html_safe
      render action: :new
    else
      BuildList.where(id: build_lists.map(&:id)).update_all(group_id: build_lists[0].id) if build_lists.size > 1
      flash[:notice] = notices.join('<br>').html_safe
      redirect_to project_build_lists_path(@project)
    end
  end

  def show
    @item_groups = @build_list.items.group_by_level
  end

  def publish
    @build_list.update_type = params[:build_list][:update_type] if params[:build_list][:update_type].present?

    if params[:attach_advisory].present? and params[:attach_advisory] != 'no' and !@build_list.advisory

      unless @build_list.update_type.in? BuildList::RELEASE_UPDATE_TYPES
        redirect_to :back, notice: t('layout.build_lists.publish_fail') and return
      end

      if params[:attach_advisory] == 'new'
        # create new advisory
        unless @build_list.associate_and_create_advisory(params[:build_list][:advisory])
          redirect_to :back, notice: t('layout.build_lists.publish_fail') and return
        end
      else
        # attach existing advisory
        a = Advisory.where(advisory_id: params[:attach_advisory]).first
        unless (a && a.attach_build_list(@build_list))
          redirect_to :back, notice: t('layout.build_lists.publish_fail') and return
        end
      end
    end

    @build_list.publisher = current_user
    do_and_back(:publish, 'publish_')
  end

  def dependent_projects
    raise CanCan::AccessDenied if @build_list.save_to_platform.personal?

    if request.post?
      prs = params[:build_list]
      if prs.present? && prs[:projects].present? && prs[:arches].present?
        project_ids = prs[:projects].select{ |k, v| v == '1'  }.keys
        arch_ids    = prs[:arches].  select{ |k, v| v == '1'  }.keys

        Resque.enqueue(
          BuildLists::DependentPackagesJob,
          @build_list.id,
          current_user.id,
          project_ids,
          arch_ids,
          {
            auto_publish_status:            prs[:auto_publish_status],
            auto_create_container:          prs[:auto_create_container],
            include_testing_subrepository:  prs[:include_testing_subrepository],
            use_cached_chroot:              prs[:use_cached_chroot],
            use_extra_tests:                prs[:use_extra_tests]
          }
        )
        flash[:notice] = t('flash.build_list.dependent_projects_job_added_to_queue')
        redirect_to build_list_path(@build_list)
      end
    end
  end

  def publish_into_testing
    @build_list.publisher = current_user
    do_and_back(:publish_into_testing, 'publish_')
  end

  def rerun_tests
    do_and_back(:rerun_tests, 'rerun_tests_')
  end

  def reject_publish
    @build_list.publisher = current_user
    do_and_back(:reject_publish, 'reject_publish_')
  end

  def create_container
    do_and_back(:publish_container, 'create_container_')
  end

  def cancel
    do_and_back(:cancel, nil, 'will_be_canceled', 'cancel_fail')
  end

  def log
    render json: {
      log: @build_list.log(params[:load_lines]),
      building: @build_list.build_started?
    }
  end

  def list
    @build_lists = @project.build_lists
    @build_lists = @build_lists.where(user_id: current_user) if params[:owner_filter] == 'true'
    @build_lists = @build_lists.where(status: [BuildList::BUILD_ERROR, BuildList::FAILED_PUBLISH, BuildList::REJECTED_PUBLISH]) if params[:status_filter] == 'true'

    @total_build_lists = @build_lists.count

    @build_lists = @build_lists.recent.paginate(page: current_page)

    render partial: 'build_lists_ajax', layout: false
  end

  def update_type
    respond_to do |format|
      format.html { render nothing: true }
      format.json do
        @build_list.update_type = params[:update_type]
        if @build_list.save
          render json: 'success', status: :ok
        else
          render json: { message: @build_list.errors.full_messages.join('. ') },
                 status: :unprocessable_entity
        end
      end
    end
  end

  protected

  def do_and_back(action, prefix, success = 'success', fail = 'fail')
    result  = @build_list.send("can_#{action}?") && @build_list.send(action)
    message = result ? success : fail
    flash[result ? :notice : :error] = t("layout.build_lists.#{prefix}#{message}")
    redirect_to :back
  end

  def find_build_list
    @build_list = BuildList.find(params[:id])
  end

  def create_from_build_list
    return if params[:build_list_id].blank?
    build_list = @project.build_lists.find(params[:build_list_id])

    params[:build_list] ||= {}
    keys = [
      :save_to_repository_id, :auto_publish_status, :include_repos,
      :extra_params, :project_version, :update_type, :auto_create_container,
      :extra_repositories, :extra_build_lists, :build_for_platform_id,
      :use_cached_chroot, :use_extra_tests, :save_buildroot,
      :include_testing_subrepository, :external_nodes
    ]
    keys.each { |key| params[:build_list][key] = build_list.send(key) }
    params[:arches] = [build_list.arch_id]
    [:owner_filter, :status_filter].each { |t| params[t] = 'true' if %w(true undefined).exclude? params[t] }
  end
end
