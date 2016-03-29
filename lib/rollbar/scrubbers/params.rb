require 'rollbar/scrubbers'


module Rollbar
  module Scrubbers
    class Params
      SKIPPED_CLASSES = [Tempfile]
      ATTACHMENT_CLASSES = %w(ActionDispatch::Http::UploadedFile Rack::Multipart::UploadedFile).freeze

      def self.call(*args)
        new.call(*args)
      end

      def call(params, extra_fields = [])
        return {} unless params

        config = Rollbar.configuration.scrub_fields

        scrub(params, build_scrub_options(config, extra_fields))
      end

      private

      def build_scrub_options(config, extra_fields)
        ary_config = Array(config)

        {
          :fields_regex => build_fields_regex(ary_config, extra_fields),
          :scrub_all => ary_config.include?(Rollbar::SCRUB_ALL)
        }
      end

      def build_fields_regex(config, extra_fields)
        fields = config.find_all { |f| f.is_a?(String) || f.is_a?(Symbol) }
        fields += Array(extra_fields)

        return unless fields.any?

        Regexp.new(fields.map { |val| Regexp.escape(val.to_s).to_s }.join('|'), true)
      end

      def scrub(params, options)
        fields_regex = options[:fields_regex]

        params.to_hash.inject({}) do |result, (key, value)|
          if fields_regex && fields_regex =~ Rollbar::Encoding.encode(key).to_s
            result[key] = Rollbar::Scrubbers.scrub_value(value)
          elsif value.is_a?(Hash)
            result[key] = scrub(sensitive_params, value)
          elsif value.is_a?(Array)
            result[key] = value.map do |v|
              v.is_a?(Hash) ? scrub(v, options) : rollbar_filtered_param_value(v, options)
            end
          elsif skip_value?(value)
            result[key] = "Skipped value of class '#{value.class.name}'"
          else
            result[key] = rollbar_filtered_param_value(value)
          end

          result
        end
      end

      def rollbar_filtered_param_value(value)
        if ATTACHMENT_CLASSES.include?(value.class.name)
          begin
            attachment_value(value)
          rescue
            'Uploaded file'
          end
        else
          value
        end
      end

      def attachment_value(value)
        {
          :content_type => value.content_type,
          :original_filename => value.original_filename,
          :size => value.tempfile.size
        }
      end

      def skip_value?(value)
        SKIPPED_CLASSES.any? { |klass| value.is_a?(klass) }
      end
    end
  end
end
