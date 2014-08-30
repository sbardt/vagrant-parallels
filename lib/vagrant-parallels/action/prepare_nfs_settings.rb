module VagrantPlugins
  module Parallels
    module Action
      class PrepareNFSSettings
        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new('vagrant_parallels::action::nfs')
        end

        def call(env)
          @machine = env[:machine]
          @app.call(env)

          if using_nfs?
            @logger.info("Using NFS, preparing NFS settings by reading host IP and machine IP")
            add_ips_to_env!(env)
          end
        end

        # We're using NFS if we have any synced folder with NFS configured. If
        # we are not using NFS we don't need to do the extra work to
        # populate these fields in the environment.
        def using_nfs?
          @machine.config.vm.synced_folders.any? { |_, opts| opts[:type] == :nfs }
        end

        # Extracts the proper host and guest IPs for NFS mounts and stores them
        # in the environment for the SyncedFolder action to use them in
        # mounting.
        #
        # The ! indicates that this method modifies its argument.
        def add_ips_to_env!(env)
          host_ip    = find_host_only_adapter
          machine_ip = read_machine_ip

          raise Vagrant::Errors::NFSNoHostonlyNetwork if !host_ip || !machine_ip

          env[:nfs_host_ip]    = host_ip
          env[:nfs_machine_ip] = machine_ip
        end

        # Finds first host only network adapter and returns its IP address
        #
        # @return [String] ip address of found host-only adapter
        def find_host_only_adapter
          host_only_all = @machine.provider.driver.read_host_only_interfaces
          host_only_used = @machine.provider.driver.read_network_interfaces.
            select { |_, opts| opts[:type] == :hostonly }

          host_only_used.each do |_, opts|
            host_only_all.each do |interface|
              if @machine.provider.pd_version_satisfies?('>= 10')
                name_matched = interface[:name] == opts[:hostonly]
              else
                name_matched = interface[:bound_to] == opts[:hostonly]
              end

              return interface[:ip] if name_matched
            end
          end

          nil
        end

        # Returns the IP address of the guest by looking at the first
        # enabled host only network.
        #
        # @return [String] ip address of adapter in guest
        def read_machine_ip
          ips = []
          @machine.config.vm.networks.each do |type, options|
            if type == :private_network && options[:ip].is_a?(String)
              ips << options[:ip]
            end
          end

          if ips.empty?
            raise Vagrant::Errors::NFSNoGuestIP
          end

          ips
        end
      end
    end
  end
end
