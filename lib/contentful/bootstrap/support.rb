require 'stringio'

module Contentful
  module Bootstrap
    module Support
      def self.silence_stderr
        old_stderr = $stderr
        $stderr = StringIO.new
        yield
      ensure
        $stderr = old_stderr
      end

      def self.output(text = nil, quiet = false)
        if text.nil?
          puts unless quiet
          return
        end

        puts text unless quiet
      end

      def self.input(prompt_text, no_input = false)
        return if no_input

        print prompt_text
        answer = gets.chomp
        yield answer if block_given?
      end
    end
  end
end
