class Document < ActiveRecord::Base
  belongs_to :entry
  belongs_to :language

  attr_accessible :entry, :language, :body

  validates :entry_id, presence: true, uniqueness: {
    scope: [:language_id],
    message: "already has a Document for the language and version for entry %{value}"
  }
  validates :language_id, presence: true
  validates :translated, format: {
    with: /\A(yes|partially|no)\z/,
    message: "unknown state of translation: %{value}"
  }

  before_create :create_paragraphs, :set_translated

  def original
    Document.where(language_id: Language["en"].id,
                   entry_id: self.entry_id).first
  end

  def paragraphs
    return [] if self.paragraph_id_list.nil?

    @paragraphs ||= self.paragraph_id_list.split.map{|id|
      Paragraph.find(id)
    }
  end

  def update_translated
    new_state = translation_state()
    if new_state != self.translated
      update_attribute("translated", new_state)
    end
  end

  private
  def translation_state
    states = paragraphs.map(&:translated?)
    case 
    when states.empty? then "yes"
    when states.all? then "yes"
    when states.none? then "no"
    else "partially"
    end
  end

  def set_translated
    self.translated = translation_state
    return true
  end

  def create_paragraphs
    case self.language.short_name
    when "en"
      return nil if self.body.nil?

      para_ids = split_body(self.body || "").map{|str|
        # Note: remove trailing spaces because two paragraphs
        # "abc" and "abc\n" should be regarded as the same
        str.rstrip!

        if para = Paragraph.where(body: str, language_id: self.language.id).first
          para.id
        else
          Paragraph.new.tap{|para|
            para.body = str
            para.language = self.language
            para.original = nil
            para.save!
          }.id
        end
      }
      self.paragraph_id_list = " " + para_ids.join(" ") + " "
    when "ja"
      # do not make paragraphs
    else
      orig_document = self.original
      return nil if orig_document.body.nil?

      para_ids = orig_document.paragraphs.map{|orig_paragraph|
        if para = Paragraph.where(language_id: self.language.id,
                                  original_id: orig_paragraph.id).first
          para.id
        else
          Paragraph.new.tap{|para|
            para.body = nil
            para.language = self.language
            para.original = orig_paragraph
            para.save!
          }.id
        end
      }
      self.paragraph_id_list = " " + para_ids.join(" ") + " "
    end
    return true
  end

  def split_body(body)
    ret = []
    para = ""
    in_code = false

    body.lines.each do |line|
      if in_code
        if indented?(line) || line.blank?
          para << line
        else
          in_code = false
          ret << para; para = line
        end
      else
        if line.blank?
          para << line
          ret << para unless para == "\n"; para = ""
        elsif indented?(line)
          in_code = true
          ret << para; para = line
        else
          para << line
        end
      end
    end
    ret << para
    return ret
  end

  def indented?(str)
    str =~ /\A\s+\S+/
  end
end

