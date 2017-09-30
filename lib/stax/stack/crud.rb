module Stax
  class Stack < Base

    class_option :resources, type: :array,   default: nil,   desc: 'resources IDs to allow updates'
    class_option :all,       type: :boolean, default: false, desc: 'DANGER: allow updates to all resources'

    no_commands do
      ## policy to lock the stack to all updates
      def stack_policy
        {
          Statement: [
            Effect:    'Deny',
            Action:    'Update:*',
            Principal: '*',
            Resource:  '*'
          ]
        }
      end

      ## temporary policy during updates
      def stack_policy_during_update
        {
          Statement: [
            Effect:    'Allow',
            Action:    'Update:*',
            Principal: '*',
            Resource:  stack_update_resources
          ]
        }
      end

      ## resources to unlock during update
      def stack_update_resources
        (options[:all] ? ['*'] : options[:resources]).map do |r|
          "LogicalResourceId/#{r}"
        end
      end

      ## cleanup sometimes needs to wait
      def wait_for_delete(seconds = 5)
        return unless exists?
        debug("Waiting for #{stack_name} to delete")
        loop do
          sleep(seconds)
          break unless exists?
        end
      end
    end

    desc 'create', 'create stack'
    def create
      fail_task("Stack #{stack_name} already exists") if exists?
      debug("Creating stack #{stack_name}")
      cfer_converge(stack_policy: stack_policy)
    end

    desc 'update', 'update stack'
    def update
      fail_task("Stack #{stack_name} does not exist") unless exists?
      debug("Updating stack #{stack_name}")
      cfer_converge(stack_policy_during_update: stack_policy_during_update)
    end

    desc 'delete', 'delete stack'
    def delete
      if yes? "Really delete stack #{stack_name}?", :yellow
        Cfn.delete(stack_name)
      end
    end

  end
end