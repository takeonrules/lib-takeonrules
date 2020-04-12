require_relative "../audit_wrapper"

desc "Audit built files for best practices"
task :audit, [:exit_on_failure, :depth] do |task, args|
  AuditWrapper.run(task, args) do |wrapper|
    ["audit:public", "audit:frontmatter", "audit:table_counter", "audit:yaml"].each do |task|
      wrapper.invoke(task)
    end
  end
end
namespace :audit do
  desc "Audit the table counter"
  task :table_counter, [:exit_on_failure, :depth] do |task, args|
    AuditWrapper.run(task, args) do |wrapper|
      table_numbers = `ag "{{[%<] (data_)?table" #{PROJECT_PATH} -l --ignore-dir public | xargs ag "table_number=\\"\\d+\\"" -o --nofilename | ag "\\d+" -o`.split("\n").map(&:to_i).sort
      if table_numbers.size != table_numbers.last
        wrapper.there_were_errors!(message: "Mismatch on tables counted and numbered")
      end
    end
  end
  POST_FRONTMATTER_TAGS = ['title', 'date', 'layout', 'licenses', 'tags']
  CONTENT_FRONTMATTER_TAGS = ['title']
  IS_A_POST_REGEXP = %r{/posts/\d{4}/}
  desc "Audit frontmatter for conformity"
  task :frontmatter, [:exit_on_failure, :depth] do |task, args|
    AuditWrapper.run(task, args) do |wrapper|
      TakeOnRules::Site.each_project_filename(matching: "content/**/*.*") do |filename|
        begin
          file = FileWithFrontmatterAndContent.load(filename: filename)
          set_to_use = IS_A_POST_REGEXP.match(filename) ? POST_FRONTMATTER_TAGS : CONTENT_FRONTMATTER_TAGS
          set_to_use.each do |attr|
            next if file.frontmatter[attr]
            wrapper.there_were_errors!(message: "#{filename}\tExpected '#{attr}' in frontmatter")
          end
          if file.frontmatter["licenses"]
            unless file.frontmatter["licenses"].is_a?(Array)
              wrapper.there_were_errors!(message: "#{filename}\tExpected licenses to be an Array")
            end
          end
          if file.frontmatter["headline"]
            if file.frontmatter['headline'].to_s.length > 110
              wrapper.there_were_errors!(message: "#{filename}\tExpected 'headline' length to be between 0 and 110.")
            end
          end
        rescue Psych::SyntaxError
          wrapper.there_were_errors!(message: "#{filename}\tUnable to parse frontmatter")
        end
      end
    end
  end
  desc "Audit the data/**/*.yml files"
  task :yaml, [:exit_on_failure, :depth] do |task, args|
    AuditWrapper.run(task, args) do |wrapper|
      TakeOnRules::Site.each_project_filename(matching: "data/**/*.yml") do |filename|
        begin
          FileWithFrontmatterAndContent.load(filename: filename)
        rescue Psych::SyntaxError
          wrapper.there_were_errors!(message: "#{filename}\tInvalid YAML")
        end
      end
    end
  end

  desc "Audit the public pages"
  task :public, [:exit_on_failure, :depth] do |task, args|
    AuditWrapper.run(task, args) do |wrapper|
      HUGO_SHORTCODE_DECLARATIONS = %r({{[%\<\-]).freeze
      HUGO_SHORTCODE_CLOSURE = %r([%\>\-]}}).freeze
      MARKDOWN_BOLD = /\*{2}[^\*]+\*{2}/.freeze
      MARKDOWN_LINK = /\[([^\]]*)\](http|\/|\()/.freeze
      MARKDOWN_EM = /(_[^\n_]+_)/.freeze
      MARKDOWN_STRIKETHROUGH = /(~~[^\n~]+~~)/.freeze
      HREF_DRIVETHRURPG = %r{https?:\/\/(www\.)?drivethrurpg\.com}
      DRIVETHRURPG_AFFILIATE_ID = "affiliate_id=318171"
      require 'nokogiri'
      TakeOnRules::Site.each_project_filename(matching: "public/**/*.html") do |filename|
        next if filename =~ AMP_FILENAME_REGEXP
        filename_to_report = filename.sub(PUBLIC_PATH, '')
        content = File.read(filename)
        doc = Nokogiri::HTML(content)
        body = doc.css('body')

        # p tag contains h tags
        if body.css('p h1, p h2, p h3, p h4, p h5').any?
          wrapper.there_were_errors!(message: "#{filename_to_report}\tFound H-tag nested within P-tag")
        end
        doc.css('a').each do |a_node|
          next unless a_node.attributes.key?('href')
          href = a_node.attributes['href'].value
          uri = URI.parse(href)
          if href =~ HREF_DRIVETHRURPG
            if uri.query
              next if uri.query.include?(DRIVETHRURPG_AFFILIATE_ID)
              wrapper.there_were_errors!(message: "#{filename_to_report}\tFound missing affiliate_id query parameter (has #{uri.to_s.inspect})")
            else
              wrapper.there_were_errors!(message: "#{filename_to_report}\tFound no query parameters for #{uri.to_s.inspect}")
            end
          end

          if a_node.text.include?("</a>")
            wrapper.there_were_errors!(message: "#{filename_to_report}\tFound a A-tag with a closing '<\\a>' in the text")
          end
        end

        if body.css('li p .sidenote').any?
          wrapper.there_were_errors!(message: "#{filename_to_report}\tFound sidenote nested within LI-tag")
        end

        # Audit Tables
        doc.css('table').each do |table_node|
          if table_node.css('caption').empty?
            wrapper.there_were_errors!(message: "#{filename_to_report}\tExpected CAPTION for TABLE")
          end
          if table_node.css('thead').empty?
            wrapper.there_were_errors!(message: "#{filename_to_report}\tExpected THEAD for TABLE")
          end
          if table_node.css('tbody').empty?
            wrapper.there_were_errors!(message: "#{filename_to_report}\tExpected TBODY for TABLE")
          end
        end



        # Now look to the text to see if there are problems
        body.css('code').each(&:remove) # Code is as code does, don't audit that
        body.css('a').children.each(&:remove) # A concession that an A-tags child node may have underscores
        text = body.text
        [HUGO_SHORTCODE_CLOSURE, HUGO_SHORTCODE_DECLARATIONS].each do |code|
          if text.match(code)
            wrapper.there_were_errors!(message: "#{filename_to_report}\tExpected not to match #{code}")
          end
        end

        if text =~ MARKDOWN_LINK
          wrapper.there_were_errors!(message: "#{filename_to_report}\tFound unresolved markdown link")
        end

        if text =~ MARKDOWN_BOLD
          wrapper.there_were_errors!(message: "#{filename_to_report}\tFound possible un-expanded markdown STRONG declaration (at #{$1.inspect})")
        end

        if text =~ MARKDOWN_EM
          wrapper.there_were_errors!(message: "#{filename_to_report}\tFound possible un-expanded markdown EM declaration (at #{$1.inspect})")
        end

        if content =~ MARKDOWN_STRIKETHROUGH
          wrapper.there_were_errors!(message: "#{filename_to_report}\tFound possible un-expanded markdown STRIKETHROUGH declaration (at #{$1.inspect})")
        end
      end
    end
  end

  desc "Audit images for ALT tags"
  task :images, [:exit_on_failure, :depth] do |task, args|
    AuditWrapper.run(task, args) do |wrapper|
      require 'nokogiri'
      TakeOnRules::Site.each_project_filename(matching: "public/**/*.html") do |filename|
        next if filename =~ AMP_FILENAME_REGEXP
        filename_to_report = filename.sub(PUBLIC_PATH, '')
        content = File.read(filename)
        doc = Nokogiri::HTML(content)
        doc.css('img').each do |img_node|
          next if img_node.attributes.key?("aria-hidden")
          alt = img_node.attributes['alt']&.value.to_s
          next unless alt.empty?
          wrapper.there_are_warnings!(message: "#{filename_to_report}\tWARNING: ALT attribute for IMG #{img_node.attributes['src'].value}")
        end
      end
    end
  end

  desc "Audit for apparent missing tags"
  task :css, [:exit_on_failure, :depth] do |task, args|
    AuditWrapper.run(task, args) do |wrapper|
      require 'nokogiri'
      TakeOnRules::Site.each_project_filename(matching: "public/**/*.html") do |filename|
        next if filename =~ AMP_FILENAME_REGEXP
        filename_to_report = filename.sub(PUBLIC_PATH, '')
        content = File.read(filename)
        doc = Nokogiri::HTML(content)
        [
          ".sidenote code"
          # "header > nav a img", REMOVE
          # "button[type='submit']", REMOVE
          # ".definition-list", # REMOVE
          # "figure.fullwidth figcaption", REMOVE
          # "blockquote .sidenote", KEEP
          # "blockquote .marginnote", KEEP
          # "p.subtitle" REMOVE,
          # "li .sidenote", #KEEP
          # "li .marginnote", KEEP,
        ].each do |css|
          doc.css(css).each do |img_node|
            wrapper.there_are_warnings!(message: "#{filename_to_report}\tWARNING: #{css} exists")
          end
        end
      end
    end
  end
end
