module Stormpath

  module Resource

    class Group < InstanceResource

      include Status

      NAME = "name"
      DESCRIPTION = "description"
      STATUS = "status"
      TENANT = "tenant"
      DIRECTORY = "directory"
      ACCOUNTS = "accounts"

      def get_name
        get_property NAME
      end

      def set_name name
        set_property NAME, name
      end

      def get_description
        get_property DESCRIPTION
      end

      def set_description description
        set_property DESCRIPTION, description
      end

      def get_status
        value = get_property STATUS

        if !value.nil?
          value = value.upcase
        end

        value
      end

      def set_status status

        if get_status_hash.has_key? status
          set_property STATUS, get_status_hash[status]
        end

      end

      def get_tenant
        get_resource_property TENANT, Tenant
      end

      def get_directory
        get_resource_property DIRECTORY, Directory
      end

      def get_accounts
        get_resource_property ACCOUNTS, AccountList
      end

      def add_account account

        group_membership = data_store.instantiate GroupMembership, nil
        group_membership.create account, self

      end

    end

  end

end