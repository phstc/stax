require 'base64'
require 'stax/aws/ecr'

module Stax
  module Ecr
    def self.included(thor)
      thor.desc(:ecr, 'ECR subcommands')
      thor.subcommand(:ecr, Cmd::Ecr)
    end

    def ecr_registry
      @_ecr_registry ||= "#{aws_account_id}.dkr.ecr.#{aws_region}.amazonaws.com"
    end

    def ecr_repositories
      @_ecr_repositories ||= Aws::Cfn.resources_by_type(stack_name, 'AWS::ECR::Repository')
    end

    def ecr_repository_names
      @_ecr_repository_names ||= ecr_repositories.map(&:physical_resource_id)
    end

    ## override to set an explicit repo name
    def ecr_repository_name
      @_ecr_repository_name ||= (ecr_repository_names&.first || app_name)
    end
  end

  module Cmd
    class Ecr < SubCommand

      desc 'registry', 'show ECR registry'
      def registry
        puts my.ecr_registry
      end

      ## TODO: reimplement using --password-stdin
      desc 'login', 'login to ECR registry'
      def login
        Aws::Ecr.auth.each do |auth|
          debug("Login to ECR registry #{auth.proxy_endpoint}")
          user, pass = Base64.decode64(auth.authorization_token).split(':')
          system "docker login -u #{user} -p #{pass} #{auth.proxy_endpoint}"
        end
      end

      desc 'repositories', 'list ECR repositories'
      def repositories
        print_table Aws::Ecr.repositories(repository_names: my.ecr_repository_names).map { |r|
          [r.repository_name, r.repository_uri, r.created_at]
        }
      end

      desc 'images', 'list ECR images'
      method_option :repositories, aliases: '-r', type: :array, default: nil, desc: 'list of repos'
      def images
        (options[:repositories] || my.ecr_repository_names).each do |repo|
          debug("Images in repo #{repo}")
          print_table Aws::Ecr.images(repository_name: repo).map { |i|
            [i.image_tags.join(' '), i.image_digest, human_bytes(i.image_size_in_bytes), i.image_pushed_at]
          }
        end
      end

    end
  end

end