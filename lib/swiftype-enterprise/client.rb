require 'swiftype-enterprise/configuration'
require 'swiftype-enterprise/request'
require 'swiftype-enterprise/utils'

module SwiftypeEnterprise
  # API client for the {Swiftype Enterprise API}[https://swiftype.com/enterprise-search].
  class Client
    DEFAULT_TIMEOUT = 15

    include SwiftypeEnterprise::Request

    def self.configure(&block)
      SwiftypeEnterprise.configure &block
    end

    # Create a new SwiftypeEnterprise::Client client
    #
    # @param options [Hash] a hash of configuration options that will override what is set on the SwiftypeEnterprise class.
    # @option options [String] :access_token an Access Token to use for this client
    # @option options [Numeric] :overall_timeout overall timeout for requests in seconds (default: 15s)
    # @option options [Numeric] :open_timeout the number of seconds Net::HTTP (default: 15s)
    #   will wait while opening a connection before raising a Timeout::Error
    def initialize(options={})
      @options = options
    end

    def access_token
      @options[:access_token] || SwiftypeEnterprise.access_token
    end

    def open_timeout
      @options[:open_timeout] || DEFAULT_TIMEOUT
    end

    def overall_timeout
      (@options[:overall_timeout] || DEFAULT_TIMEOUT).to_f
    end

    # Documents have fields that can be searched or filtered.
    #
    # For more information on indexing documents, see the {Content Source documentation}[https://app.swiftype.com/ent/docs/custom_sources].
    module ContentSourceDocuments
      REQUIRED_TOP_LEVEL_KEYS = [
        'external_id',
        'url',
        'title',
        'body'
      ].map!(&:freeze).to_set.freeze
      OPTIONAL_TOP_LEVEL_KEYS = [
        'created_at',
        'updated_at',
        'type',
      ].map!(&:freeze).to_set.freeze
      CORE_TOP_LEVEL_KEYS = (REQUIRED_TOP_LEVEL_KEYS + OPTIONAL_TOP_LEVEL_KEYS).freeze

      # Retrieve Document Receipts from the API by ID for the {asynchronous API}[https://app.swiftype.com/ent/docs/custom_sources]
      #
      # @param [Array<String>] receipt_ids an Array of Document Receipt IDs
      #
      # @return [Array<Hash>] an Array of Document Receipt hashes
      def document_receipts(receipt_ids)
        get('ent/document_receipts/bulk_show.json', :ids => receipt_ids.join(','))
      end

      # Index a batch of documents synchronously using the {Content Source API}[https://app.swiftype.com/ent/docs/custom_sources].
      #
      # @param [String] content_source_key the unique Content Source key as found in your Content Sources dashboard
      # @param [Array] documents an Array of Document Hashes
      # @option options [Numeric] :timeout (10) Number of seconds to wait before raising an exception
      #
      # @return [Array<Hash>] an Array of processed Document Receipt hashes
      #
      # @raise [Timeout::Error] when timeout expires waiting for receipts
      def index_documents(content_source_key, documents, options = {})
        documents = Array(documents).map! { |document| validate_and_normalize_document(document) }

        res = async_create_or_update_documents(content_source_key, documents)
        receipt_ids = res['document_receipts'].map { |a| a['id'] }

        poll(options) do
          receipts = document_receipts(receipt_ids)
          flag = receipts.all? { |a| a['status'] != 'pending' }
          flag ? receipts : false
        end
      end

      # Index a batch of documents asynchronously using the {Content Source API}[https://app.swiftype.com/ent/docs/custom_sources].
      #
      # @param [String] content_source_key the unique Content Source key as found in your Content Sources dashboard
      # @param [Array] documents an Array of Document Hashes
      # @param [Hash] options additional options
      #
      # @return [Array<String>] an Array of Document Receipt IDs pending completion
      def async_index_documents(content_source_key, documents, options = {})
        documents = Array(documents).map! { |document| validate_and_normalize_document(document) }

        res = async_create_or_update_documents(content_source_key, documents)
        res['document_receipts'].map { |a| a['id'] }
      end

      # Destroy a batch of documents given a list of external IDs
      #
      # @param [Array<String>] document_ids an Array of Document External IDs
      #
      # @return [Array<Hash>] an Array of Document destroy result hashes
      def destroy_documents(content_source_key, document_ids)
        document_ids = Array(document_ids)
        post("ent/sources/#{content_source_key}/documents/bulk_destroy.json", document_ids)
      end

      private
      def async_create_or_update_documents(content_source_key, documents)
        post("ent/sources/#{content_source_key}/documents/bulk_create.json", documents)
      end

      def validate_and_normalize_document(document)
        document = Utils.stringify_keys(document)
        missing_keys = REQUIRED_TOP_LEVEL_KEYS - document.keys
        raise SwiftypeEnterprise::InvalidDocument.new("missing required fields (#{missing_keys.to_a.join(', ')})") if missing_keys.any?

        normalized_document = {}

        body_content = [document.delete('body')]
        document.each do |key, value|
          if CORE_TOP_LEVEL_KEYS.include?(key)
            normalized_document[key] = value
          else
            body_content << "#{key}: #{value}"
          end
        end
        normalized_document['body'] = body_content.join("\n")

        normalized_document
      end
    end

    include SwiftypeEnterprise::Client::ContentSourceDocuments
  end
end
