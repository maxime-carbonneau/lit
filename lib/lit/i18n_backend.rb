require 'i18n'

module Lit
  class I18nBackend
    include I18n::Backend::Simple::Implementation

    attr_reader :cache

    def initialize(cache)
      @cache = cache
      @available_locales_cache = nil
    end

    def translate(locale, key, options = {})
      content = super(locale, key, options.merge(fallback: true))
      if Lit.all_translations_are_html_safe && content.respond_to?(:html_safe)
        content.html_safe
      else
        content
      end
    end

    def available_locales
      return @available_locales_cache unless @available_locales_cache.nil?
      locales = ::Rails.configuration.i18n.available_locales
      if locales && !locales.empty?
        @available_locales_cache = locales.map(&:to_sym)
      else
        @available_locales_cache = Lit::Locale.ordered.visible.map { |l| l.locale.to_sym }
      end
      @available_locales_cache
    end

    def reset_available_locales_cache
      @available_locales_cache = nil
    end

    # Stores the given translations.
    #
    # @param [String] locale the locale (ie "en") to store translations for
    # @param [Hash] data nested key-value pairs to be added as blurbs
    def store_translations(locale, data, options = {})
      super
      locales = ::Rails.configuration.i18n.available_locales
      if !locales || locales.map(&:to_s).include?(locale.to_s)
        store_item(locale, data)
      end
    end

    private

    def lookup(locale, key, scope = [], options = {})
      parts = I18n.normalize_keys(locale, key, scope, options[:separator])
      key_with_locale = parts.join('.')

      ## check in cache or in simple backend
      content = @cache[key_with_locale] || super
      return content if parts.size <= 1
      
      # According to the context and the options, will we created the key
      condition = Lit.init_lit ||
                  Lit.discover_new_translation == true ||
                  Lit.discover_new_translation == :default && options[:default].present?

      if !@cache.has_key?(key_with_locale) and condition
        new_content = @cache.init_key_with_value(key_with_locale, content)
        content = new_content if content.nil? # Content can change when Lit.humanize is true for example

        if content.nil? && options[:default].present?
          if options[:default].is_a?(Array)
            default = options[:default].map do |key|
              if key.is_a?(Symbol)
                I18n.normalize_keys(nil, key.to_s, options[:scope], options[:separator]).join('.').to_sym
              else
                key
              end
            end
          else
            default = options[:default]
          end

          @cache[key_with_locale] = default
          content = @cache[key_with_locale]
        end
      end
      ## return translated content
      content
    end

    def store_item(locale, data, scope = [])
      if data.respond_to?(:to_hash)
        data.to_hash.each do |key, value|
          store_item(locale, value, scope + [key])
        end
      elsif data.respond_to?(:to_str)
        key = ([locale] + scope).join('.')
        @cache[key] ||= data
      elsif data.nil?
        key = ([locale] + scope).join('.')
        @cache.delete_locale(key)
      end
    end

    def load_translations(*filenames)
      @cache.load_all_translations
      super
    end
  end
end
