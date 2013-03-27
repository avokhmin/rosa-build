class MassBuild < ActiveRecord::Base
  belongs_to :platform
  belongs_to :user
  has_many :build_lists, :dependent => :destroy

  scope :by_platform, lambda { |platform| where(:platform_id => platform.id) }
  scope :outdated, where("#{table_name}.created_at < ?", Time.now + 1.day - BuildList::MAX_LIVE_TIME)

  attr_accessor :arches
  attr_accessible :arches, :auto_publish, :projects_list

  validates :platform_id, :arch_names, :name, :user_id, :projects_list, :presence => true
  validates_inclusion_of :auto_publish, :in => [true, false]

  after_create :build_all
  before_validation :set_data

  COUNT_STATUSES = [
    :build_lists,
    :build_published,
    :build_pending,
    :build_started,
    :build_publish,
    :build_error,
    :success,
    :build_canceled
  ]

  def build_all
    # later with resque
    arches_list = arch_names ? Arch.where(:name => arch_names.split(', ')) : Arch.all
    auto_publish ||= false

    projects_list.lines.each do |name|
      next if name.blank?
      name.chomp!; name.strip!

      if project = Project.joins(:repositories).where('repositories.id in (?)', platform.repository_ids).find_by_name(name)
        begin
          return if self.reload.stop_build
          arches_list.each do |arch|
            rep = (project.repositories & platform.repositories).first
            project.build_for(platform, rep.id, user, arch, auto_publish, self.id, 0)
          end
        rescue RuntimeError, Exception
        end
      else
        MassBuild.increment_counter :missed_projects_count, id
        list = (missed_projects_list || '') << "#{name}\n"
        update_column :missed_projects_list, list
      end
    end
  end
  later :build_all, :queue => :clone_build

  def generate_failed_builds_list
    report = ""
    BuildList.where(
      :status => BuildList::BUILD_ERROR,
      :mass_build_id => self.id
    ).includes(:project, :arch).find_in_batches(:batch_size => 100) do |build_lists|
      build_lists.each do |build_list|
        report << "ID: #{build_list.id}; "
        report << "PROJECT_NAME: #{build_list.project.name}; "
        report << "ARCH: #{build_list.arch.name}\n"
      end
    end
    report
  end

  def cancel_all
    update_column(:stop_build, true)
    build_lists.find_each(:batch_size => 100) do |bl|
      bl.cancel
    end
  end
  later :cancel_all, :queue => :clone_build

  def publish_success_builds
    publish BuildList::SUCCESS, BuildList::FAILED_PUBLISH
  end
  later :publish_success_builds, :queue => :clone_build

  def publish_test_faild_builds
    publish BuildList::TESTS_FAILED
  end
  later :publish_test_faild_builds, :queue => :clone_build

  private

  def publish(*statuses)
    build_lists.where(:status => statuses).order(:id).find_in_batches(:batch_size => 50) do |bls|
      bls.each{ |bl| bl.can_publish? && bl.now_publish }
    end
  end

  def set_data
    if new_record?
      self.name = "#{Time.now.utc.to_date.strftime("%d.%b")}-#{platform.name}"
      self.arch_names = Arch.where(:id => self.arches).map(&:name).join(", ")
    end
  end
end
