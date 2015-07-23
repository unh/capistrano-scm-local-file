namespace :local_file do
  set :rsync_src, 'tmp/deploy'
  set :rsync_dest, 'shared/deploy'

  set :rsync_dest_fullpath, -> {
    path = fetch(:rsync_dest)
    path = "#{deploy_to}/#{path}" if path && path !~ /^\//
    path
  }

  set :rsync_options, fetch(:rsync_options, %w(
    --recursive
    --delete
    --links
    --progress
    --delete-excluded
    --exclude .git*
    --exclude .svn*
    --ignore-times
  ))


  def strategy
    @strategy ||= Capistrano::LocalFile.new(
      self,
      fetch(:local_file_strategy, Capistrano::LocalFile::DefaultStrategy))
  end

  desc 'Check if the path to save the local_file has been created'
  task :check do
    on release_roles :all do
      info "running local_file:check"
      strategy.check
    end
  end

  desc 'Create the path for the local_file if it does not exist'
  task clone: :'local_file:check' do
    on release_roles :all do
      if strategy.test
        info t(:mirror_exists, at: repo_path)
      else
        within deploy_path do
          debug "We're not cloning anything, just creating #{repo_path}"
          strategy.clone
        end
      end
    end
  end

  desc 'Upload the local_file'
  task update: :'local_file:clone' do
    on release_roles :all do
      run_locally do
        execute :rm, '-rf', fetch(:rsync_src)
        execute :mkdir, '-p', fetch(:rsync_src)
        execute :tar, '-xvzf', fetch(:repo_url), "-C", fetch(:rsync_src)
      end
    end

    last_rsync_to = nil
    release_roles(:all).each do |role|
      unless Capistrano::Configuration.env.filter(role).roles_array.empty?
        run_locally do
          user = "#{role.user}@" if !role.user.nil?
          rsync_options = "#{fetch(:rsync_options).join(' ')}"
          rsync_from = "#{fetch(:rsync_src)}/"
          rsync_to = "#{user}#{role.hostname}:#{fetch(:rsync_dest_fullpath) || release_path}"

          unless rsync_to == last_rsync_to
            execute :rsync, rsync_options, rsync_from, rsync_to
            last_rsync_to = rsync_to
          end
        end
      end
    end
  end

  desc 'Copy repo to releases'
  task create_release: :'local_file:update' do
    on release_roles :all do
      info 'running task local_file:create_release'
      within "#{fetch(:rsync_dest_fullpath)}" do
        execute :mkdir, '-p', release_path
        strategy.release
      end
    end
  end

  desc 'Determine the revision that will be deployed'
  task :set_current_revision do
    on release_roles :all do
      within "#{fetch(:rsync_dest_fullpath)}" do
        set :current_revision, strategy.fetch_revision
      end
    end
  end
end
