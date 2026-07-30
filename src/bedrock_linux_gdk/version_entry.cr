module BedrockLinuxGdk
  record VersionEntry,
    tag : String,
    beta : Bool,
    size_mib : Int32 do
    LINE = /^\s*(\S+)\s+(stable|beta)\s+(\d+)\s+MiB\s*$/

    def self.parse(line : String) : VersionEntry?
      match = LINE.match(line)
      return unless match

      new(
        tag: match[1],
        beta: match[2] == "beta",
        size_mib: match[3].to_i
      )
    end

    def display : String
      suffix = beta ? "  ·  PREVIEW" : ""
      "#{formatted_tag}#{suffix}"
    end

    private def formatted_tag : String
      value = tag.sub(/^v/, "")
      pieces = value.split('.')
      return value unless pieces.size >= 3 && pieces[0] == "1"

      minor = pieces[1].to_i?
      return value unless minor
      if !beta && pieces.size == 4
        [pieces[1], pieces[2]].join('.')
      elsif minor >= 22
        pieces[1..].join('.')
      else
        value
      end
    end
  end
end
