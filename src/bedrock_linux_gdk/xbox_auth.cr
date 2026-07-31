require "base64"
require "http/client"
require "json"
require "uri/params"
require "uuid"

module BedrockLinuxGdk
  module XboxAuth
    extend self

    CLIENT_ID   = "0000000048183522"
    SCOPE       = "service::user.auth.xboxlive.com::MBI_SSL"
    CONNECT_URL = "https://login.live.com/oauth20_connect.srf"
    TOKEN_URL   = "https://login.live.com/oauth20_token.srf"
    REMOTE_URL  = "https://login.live.com/oauth20_remoteconnect.srf"

    record Session, refresh_token : String, user_id : String, gamertag : String

    def sign_in(root : String, &device : String, String ->) : Session
      response = post_form(CONNECT_URL, {
        "client_id"     => CLIENT_ID,
        "scope"         => SCOPE,
        "response_type" => "device_code",
      })
      device_code = required_string(response, "device_code")
      user_code = required_string(response, "user_code")
      verification = "#{REMOTE_URL}?#{URI::Params.encode({"otc" => user_code})}"
      yield verification, user_code

      interval = optional_i64(response, "interval").try(&.to_i) || 5
      interval = 1 if interval < 1
      expires = optional_i64(response, "expires_in").try(&.to_i) || 900
      deadline = Time.instant + expires.seconds
      token = nil.as(JSON::Any?)

      while Time.instant < deadline
        sleep interval.seconds
        candidate = post_form(TOKEN_URL, {
          "client_id"   => CLIENT_ID,
          "grant_type"  => "device_code",
          "device_code" => device_code,
        }, allow_error: true)
        case optional_string(candidate, "error")
        when "authorization_pending"
          next
        when "slow_down"
          interval += 5
          next
        when nil
          token = candidate
          break
        else
          raise optional_string(candidate, "error_description") ||
                "Microsoft rejected sign-in."
        end
      end
      raise "Microsoft sign-in timed out." unless token
      store_session(root, token.not_nil!)
    end

    def refresh(root : String) : Session
      credentials = read_json(credentials_path(root))
      refresh_token = required_string(credentials, "refresh_token")
      begin
        token = post_form(TOKEN_URL, {
          "client_id"     => CLIENT_ID,
          "scope"         => SCOPE,
          "grant_type"    => "refresh_token",
          "refresh_token" => refresh_token,
        })
        store_session(root, token)
      rescue error
        cached = cached_session(root)
        return cached if cached
        raise error
      end
    end

    def cached_session(root : String) : Session?
      credentials = read_json(credentials_path(root))
      payload = read_json(preauth_path(root))
      return unless cache_valid?(payload)
      Session.new(
        required_string(credentials, "refresh_token"),
        required_string(payload, "xbl_xuid"),
        optional_string(payload, "xbl_gamertag") || ""
      )
    rescue
      nil
    end

    def preauth_path(root : String) : String
      File.join(root, "auth", "xbox-session.json")
    end

    def oauth_path(root : String) : String
      File.join(root, "auth", "oauth-session")
    end

    def bridge_path(root : String) : String
      File.join(root, "auth", "xbox-bridge-session")
    end

    def seed_refresh_token(root : String, token : String) : Nil
      raise "Microsoft refresh token is invalid." if token.empty? ||
                                                     token.includes?('\0') ||
                                                     token.includes?('\n') ||
                                                     token.includes?('\r')
      path = File.join(root, "compatdata", "pfx", "system.reg")
      content = File.read(path)
      section = "[Software\\\\Wine\\\\WineGDK]"
      escaped = token.gsub('\\', "\\\\").gsub('"', "\\\"")
      value = "\"RefreshToken\"=\"#{escaped}\""
      lines = content.lines(chomp: false)
      start = lines.index { |line| line.starts_with?(section) }

      if start
        finish = ((start + 1)...lines.size).find do |index|
          lines[index].starts_with?('[')
        end || lines.size
        existing = ((start + 1)...finish).find do |index|
          lines[index].starts_with?("\"RefreshToken\"=")
        end
        if existing
          lines[existing] = "#{value}\n"
        else
          lines.insert(finish, "#{value}\n")
        end
      else
        lines << "\n" unless lines.last?.to_s.ends_with?('\n')
        lines << "#{section} #{Time.utc.to_unix}\n"
        lines << "#{value}\n"
      end

      temporary = "#{path}.new"
      File.write(temporary, lines.join, perm: 0o600)
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if temporary && File.file?(temporary)
    end

    private def store_session(root : String, token : JSON::Any) : Session
      refresh_token = required_string(token, "refresh_token")
      access_token = required_string(token, "access_token")
      expires_in = optional_i64(token, "expires_in") || 3600_i64
      raise "Microsoft authentication returned an invalid expiration." if expires_in <= 0
      payload = build_preauth(
        root,
        access_token,
        refresh_token,
        Time.utc.to_unix + expires_in
      )
      write_oauth_session(
        root,
        access_token,
        refresh_token,
        Time.utc.to_unix + expires_in
      )
      write_bridge_session(root, payload)
      user_id = required_string(payload, "xbl_xuid")
      gamertag = optional_string(payload, "xbl_gamertag") || ""

      write_private_json(preauth_path(root), payload)
      write_private_json(
        credentials_path(root),
        JSON.parse({
          "refresh_token" => refresh_token,
          "updated_at"    => Time.utc.to_unix,
        }.to_json)
      )
      Session.new(refresh_token, user_id, gamertag)
    end

    private def write_oauth_session(
      root : String,
      access_token : String,
      refresh_token : String,
      expiry : Int64,
    ) : Nil
      values = {access_token, refresh_token}
      raise "Microsoft authentication returned invalid credentials." if values.any? do |value|
        value.empty? || value.includes?('\0') || value.includes?('\n') ||
          value.includes?('\r')
      end
      path = oauth_path(root)
      temporary = "#{path}.tmp"
      Dir.mkdir_p(File.dirname(path), 0o700)
      File.write(
        temporary,
        "#{expiry}\n#{access_token}\n#{refresh_token}\n",
        perm: 0o600
      )
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if temporary && File.file?(temporary)
    end

    private def write_bridge_session(root : String, payload : JSON::Any) : Nil
      privileges = payload.as_h.has_key?("xbl_privileges") ? "1" : "0"
      field_names = %w(
        device_token device_id ecc_private_blob_b64
        user_token xbl_token xbl_xuid xbl_gamertag xbl_modern_gamertag
        xbl_modern_gamertag_suffix xbl_unique_modern_gamertag xbl_age_group
        xbl_uhs xbl_privileges user_token_expiry_epoch xbl_token_expiry_epoch
        achievements_token achievements_uhs achievements_expiry_epoch
        sisu_token sisu_uhs sisu_rp sisu_expiry_epoch
        mp_token mp_uhs mp_rp mp_expiry_epoch
        realms_token realms_uhs realms_rp realms_expiry_epoch
        lic_token lic_uhs lic_rp lic_expiry_epoch
      )
      fields = field_names.map { |name| optional_string(payload, name).to_s }
      privileges_index = field_names.index("xbl_privileges").not_nil!
      fields.insert(privileges_index, privileges)
      fields.each do |value|
        raise "Xbox authentication returned invalid credentials." if
          value.includes?('\0') || value.bytesize > UInt32::MAX
      end

      path = bridge_path(root)
      temporary = "#{path}.tmp"
      Dir.mkdir_p(File.dirname(path), 0o700)
      File.open(temporary, "wb", perm: 0o600) do |file|
        file << "BLGDKXB2"
        file.write_bytes(fields.size.to_u32, IO::ByteFormat::LittleEndian)
        fields.each do |value|
          file.write_bytes(value.bytesize.to_u32, IO::ByteFormat::LittleEndian)
          file << value
        end
      end
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if temporary && File.file?(temporary)
    end

    private def build_preauth(
      root : String,
      access_token : String,
      refresh_token : String,
      oauth_expiry : Int64,
    ) : JSON::Any
      auth_dir = File.join(root, "auth")
      Dir.mkdir_p(auth_dir, 0o700)
      key_path = File.join(auth_dir, "device-key.pem")
      device_id_path = File.join(auth_dir, "device-id")
      ensure_key(key_path)
      public_x, public_y, private_d = key_components(key_path)
      device_id = if File.file?(device_id_path)
                    File.read(device_id_path).strip
                  else
                    value = "{#{UUID.random}}"
                    File.write(device_id_path, "#{value}\n", perm: 0o600)
                    value
                  end
      raise "Stored Xbox device identity is invalid." unless device_id.matches?(
                                                               /^\{[0-9a-fA-F-]{36}\}$/
                                                             )

      proof = {
        "alg" => "ES256",
        "crv" => "P-256",
        "kty" => "EC",
        "use" => "sig",
        "x"   => Base64.strict_encode(public_x),
        "y"   => Base64.strict_encode(public_y),
      }
      device = xbox_post(
        "https://device.auth.xboxlive.com/device/authenticate",
        key_path,
        device_body(device_id, proof)
      )
      device_token = required_string(device, "Token")

      user = xbox_post(
        "https://user.auth.xboxlive.com/user/authenticate",
        key_path,
        user_body(access_token)
      )
      user_token = required_string(user, "Token")
      achievements = xbox_post(
        "https://xsts.auth.xboxlive.com/xsts/authorize",
        key_path,
        xsts_body(user_token, "http://xboxlive.com")
      )

      profile = authorization(
        xbox_post(
          "https://sisu.xboxlive.com/authorize",
          key_path,
          sisu_body(access_token, device_token, proof, "http://xboxlive.com")
        )
      )
      profile_claims = xui_claims(profile)

      playfab = authorization(
        xbox_post(
          "https://sisu.xboxlive.com/authorize",
          key_path,
          sisu_body(
            access_token,
            device_token,
            proof,
            "https://b980a380.minecraft.playfabapi.com/"
          )
        )
      )
      multiplayer = authorization(
        xbox_post(
          "https://sisu.xboxlive.com/authorize",
          key_path,
          sisu_body(
            access_token,
            device_token,
            proof,
            "https://multiplayer.minecraft.net/"
          )
        )
      )
      realms = authorization(
        xbox_post(
          "https://sisu.xboxlive.com/authorize",
          key_path,
          sisu_body(
            access_token,
            device_token,
            proof,
            "https://pocket.realms.minecraft.net/"
          )
        )
      )
      licensing = begin
        authorization(
          xbox_post(
            "https://sisu.xboxlive.com/authorize",
            key_path,
            sisu_body(
              access_token,
              device_token,
              proof,
              "http://licensing.xboxlive.com"
            )
          )
        )
      rescue
        nil
      end

      fields = {} of String => String
      fields["oauth_token"] = access_token
      fields["refresh_token"] = refresh_token
      fields["oauth_expiry_epoch"] = oauth_expiry.to_s
      fields["device_id"] = device_id
      fields["ecc_private_blob_b64"] = Base64.strict_encode(
        ecc_private_blob(public_x, public_y, private_d)
      )
      put_token(fields, "device_token", device)
      put_token(fields, "user_token", user)
      put_sisu(
        fields,
        "achievements",
        "http://xboxlive.com",
        achievements
      )
      put_token(fields, "xbl_token", profile)
      put_claim(fields, "xbl_xuid", profile_claims, "xid")
      put_claim(fields, "xbl_gamertag", profile_claims, "gtg")
      put_claim(fields, "xbl_age_group", profile_claims, "agg")
      put_claim(fields, "xbl_uhs", profile_claims, "uhs")
      put_claim(fields, "xbl_modern_gamertag", profile_claims, "mgt")
      put_claim(fields, "xbl_modern_gamertag_suffix", profile_claims, "mgs")
      put_claim(fields, "xbl_unique_modern_gamertag", profile_claims, "umg")
      if privileges = optional_string(profile_claims, "prv")
        normalized = privileges.split(/[\s,]+/)
          .select(&.matches?(/^\d{1,10}$/))
          .map(&.to_u64)
          .select(&.<=(UInt32::MAX))
          .uniq
          .sort
          .join(" ")
        fields["xbl_privileges"] = normalized
      end
      put_sisu(
        fields,
        "sisu",
        "https://b980a380.minecraft.playfabapi.com/",
        playfab
      )
      put_sisu(
        fields,
        "mp",
        "https://multiplayer.minecraft.net/",
        multiplayer
      )
      put_sisu(
        fields,
        "realms",
        "https://pocket.realms.minecraft.net/",
        realms
      )
      if licensing
        put_sisu(fields, "lic", "http://licensing.xboxlive.com", licensing)
      end
      fields["obtained"] = Time.utc.to_unix.to_s

      required = %w(
        oauth_token refresh_token oauth_expiry_epoch
        device_token user_token xbl_token xbl_xuid xbl_uhs
        achievements_token achievements_uhs
        sisu_token sisu_uhs mp_token mp_uhs realms_token realms_uhs
      )
      missing = required.reject { |name| !fields[name]?.to_s.empty? }
      unless missing.empty?
        raise "Xbox authentication returned incomplete credentials: #{missing.join(", ")}."
      end
      JSON.parse(fields.to_json)
    end

    private def device_body(
      device_id : String,
      proof : Hash(String, String),
    ) : String
      {
        "RelyingParty" => "http://auth.xboxlive.com",
        "TokenType"    => "JWT",
        "Properties"   => {
          "AuthMethod" => "ProofOfPossession",
          "Id"         => device_id,
          "DeviceType" => "Win32",
          "Version"    => "10.0.22631",
          "ProofKey"   => proof,
        },
      }.to_json
    end

    private def user_body(access_token : String) : String
      {
        "RelyingParty" => "http://auth.xboxlive.com",
        "TokenType"    => "JWT",
        "Properties"   => {
          "AuthMethod" => "RPS",
          "SiteName"   => "user.auth.xboxlive.com",
          "RpsTicket"  => "t=#{access_token}",
        },
      }.to_json
    end

    private def sisu_body(
      access_token : String,
      device_token : String,
      proof : Hash(String, String),
      relying_party : String,
    ) : String
      {
        "AccessToken"          => "t=#{access_token}",
        "AppId"                => CLIENT_ID,
        "deviceToken"          => device_token,
        "Sandbox"              => "RETAIL",
        "UseModernGamertag"    => true,
        "SiteName"             => "user.auth.xboxlive.com",
        "RelyingParty"         => relying_party,
        "OfferTermsAcceptance" => true,
        "AcceptOffers"         => true,
        "ProofKey"             => proof,
      }.to_json
    end

    private def xsts_body(user_token : String, relying_party : String) : String
      {
        "RelyingParty" => relying_party,
        "TokenType"    => "JWT",
        "Properties"   => {
          "SandboxId"  => "RETAIL",
          "UserTokens" => [user_token],
        },
      }.to_json
    end

    private def xbox_post(url : String, key_path : String, body : String) : JSON::Any
      path = URI.parse(url).path
      signature = sign_request(key_path, "POST", path, body)
      response = http_post(
        url,
        HTTP::Headers{
          "User-Agent"             => "XAL Xbox Live Game (Windows; SDK; 1.0.0.0)",
          "Content-Type"           => "application/json",
          "x-xbl-contract-version" => "1",
          "Signature"              => signature,
        },
        body
      )
      parsed = JSON.parse(response.body)
      unless response.success?
        code = optional_i64(parsed, "XErr") || response.status_code
        raise "Xbox authentication failed (#{code})."
      end
      parsed
    rescue error : JSON::ParseException
      raise "Xbox authentication returned invalid data."
    end

    private def post_form(
      url : String,
      fields : Hash(String, String),
      allow_error : Bool = false,
    ) : JSON::Any
      response = http_post(
        url,
        HTTP::Headers{
          "Content-Type" => "application/x-www-form-urlencoded",
          "User-Agent"   => "bedrock-linux-gdk",
        },
        URI::Params.encode(fields)
      )
      parsed = JSON.parse(response.body)
      unless response.success? || allow_error
        raise optional_string(parsed, "error_description") ||
              "Microsoft authentication failed (HTTP #{response.status_code})."
      end
      parsed
    rescue error : JSON::ParseException
      raise "Microsoft authentication returned invalid data."
    end

    private def authorization(response : JSON::Any) : JSON::Any
      value = response["AuthorizationToken"]?
      raise "Xbox authorization token is missing." unless value && value.as_h?
      value
    end

    private def http_post(
      url : String,
      headers : HTTP::Headers,
      body : String,
    ) : HTTP::Client::Response
      uri = URI.parse(url)
      client = HTTP::Client.new(uri)
      client.connect_timeout = 10.seconds
      client.read_timeout = 20.seconds
      client.write_timeout = 20.seconds
      client.post(uri.request_target, headers, body)
    ensure
      client.try(&.close)
    end

    private def xui_claims(response : JSON::Any) : JSON::Any
      claims = response["DisplayClaims"]?.try(&.["xui"]?).try(&.as_a?)
      value = claims.try(&.first?)
      raise "Xbox account claims are missing." unless value && value.as_h?
      value
    end

    private def put_token(
      fields : Hash(String, String),
      prefix : String,
      response : JSON::Any,
    ) : Nil
      fields[prefix] = required_string(response, "Token")
      expiry = required_string(response, "NotAfter")
      fields["#{prefix}_expiry"] = expiry
      fields["#{prefix}_expiry_epoch"] = expiry_epoch(expiry)
    end

    private def put_sisu(
      fields : Hash(String, String),
      prefix : String,
      relying_party : String,
      response : JSON::Any,
    ) : Nil
      fields["#{prefix}_rp"] = relying_party
      fields["#{prefix}_token"] = required_string(response, "Token")
      expiry = required_string(response, "NotAfter")
      fields["#{prefix}_expiry"] = expiry
      fields["#{prefix}_expiry_epoch"] = expiry_epoch(expiry)
      fields["#{prefix}_uhs"] = required_string(xui_claims(response), "uhs")
    end

    private def put_claim(
      fields : Hash(String, String),
      field : String,
      claims : JSON::Any,
      claim : String,
    ) : Nil
      if value = optional_string(claims, claim)
        fields[field] = value
      end
    end

    private def cache_valid?(payload : JSON::Any) : Bool
      %w(
        oauth_token refresh_token device_token device_id ecc_private_blob_b64
        user_token xbl_token xbl_xuid achievements_token sisu_token mp_token
        realms_token
      ).all? { |field| !optional_string(payload, field).to_s.empty? } &&
        %w(
          oauth_expiry_epoch device_token_expiry_epoch user_token_expiry_epoch
          xbl_token_expiry_epoch achievements_expiry_epoch
          sisu_token_expiry_epoch
          mp_token_expiry_epoch realms_token_expiry_epoch
        ).all? do |field|
          (optional_string(payload, field).try(&.to_i64?) || 0_i64) >
            Time.utc.to_unix + 60
        end
    end

    private def expiry_epoch(raw : String) : String
      normalized = raw.gsub(/(\.\d{6})\d+(?=Z|[+-]\d{2}:\d{2}$)/, "\\1")
      Time.parse_rfc3339(normalized).to_unix.to_s
    rescue
      raise "Xbox authentication returned an invalid expiration time."
    end

    private def sign_request(
      key_path : String,
      method : String,
      path : String,
      body : String,
    ) : String
      timestamp = ((Time.utc.to_unix + 11_644_473_600_i64) *
                   10_000_000_i64).to_u64
      input = IO::Memory.new
      input.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      input.write_byte(0_u8)
      input.write_bytes(timestamp, IO::ByteFormat::BigEndian)
      input.write_byte(0_u8)
      input << method
      input.write_byte(0_u8)
      input << path
      input.write_byte(0_u8)
      input.write_byte(0_u8)
      input << body
      input.write_byte(0_u8)

      signature = IO::Memory.new
      errors = IO::Memory.new
      status = Process.run(
        openssl,
        ["dgst", "-sha256", "-sign", key_path],
        input: IO::Memory.new(input.to_slice),
        output: signature,
        error: errors
      )
      raise "Could not sign Xbox request." unless status.success?
      r, s = parse_der_signature(signature.to_slice)
      blob = IO::Memory.new
      blob.write_bytes(1_u32, IO::ByteFormat::BigEndian)
      blob.write_bytes(timestamp, IO::ByteFormat::BigEndian)
      blob.write(r)
      blob.write(s)
      Base64.strict_encode(blob.to_slice)
    end

    private def ensure_key(path : String) : Nil
      return if File.file?(path)
      temporary = "#{path}.new"
      status = Process.run(
        openssl,
        ["ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", temporary],
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      )
      raise "Could not create Xbox device key." unless status.success?
      File.chmod(temporary, 0o600)
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if temporary && File.file?(temporary)
    end

    private def key_components(path : String) : Tuple(Bytes, Bytes, Bytes)
      output = IO::Memory.new
      errors = IO::Memory.new
      status = Process.run(
        openssl,
        ["ec", "-in", path, "-text", "-noout"],
        output: output,
        error: errors
      )
      raise "Could not read Xbox device key." unless status.success?

      private_hex = String::Builder.new
      public_hex = String::Builder.new
      target = nil.as(Symbol?)
      output.to_s.each_line do |line|
        stripped = line.strip
        case stripped
        when "priv:"
          target = :private
        when "pub:"
          target = :public
        when .starts_with?("ASN1 OID:"), .starts_with?("NIST CURVE:")
          target = nil
        else
          if target && stripped.matches?(/^(?:[0-9a-fA-F]{2}:?)+$/)
            clean = stripped.delete(':')
            target == :private ? private_hex << clean : public_hex << clean
          end
        end
      end
      private_d = hex_bytes(private_hex.to_s)
      public = hex_bytes(public_hex.to_s)
      unless private_d.size == 32 && public.size == 65 && public[0] == 4
        raise "Xbox device key has invalid components."
      end
      {public[1, 32], public[33, 32], private_d}
    end

    private def parse_der_signature(bytes : Bytes) : Tuple(Bytes, Bytes)
      offset = 0
      raise "Invalid Xbox signature." unless bytes[offset]? == 0x30
      offset += 1
      _, offset = der_length(bytes, offset)
      raise "Invalid Xbox signature." unless bytes[offset]? == 0x02
      offset += 1
      r_size, offset = der_length(bytes, offset)
      r = normalize_integer(bytes[offset, r_size])
      offset += r_size
      raise "Invalid Xbox signature." unless bytes[offset]? == 0x02
      offset += 1
      s_size, offset = der_length(bytes, offset)
      s = normalize_integer(bytes[offset, s_size])
      {r, s}
    end

    private def der_length(bytes : Bytes, offset : Int32) : Tuple(Int32, Int32)
      first = bytes[offset]?.try(&.to_i) ||
              raise "Invalid Xbox signature."
      offset += 1
      return {first, offset} if first < 0x80
      count = first & 0x7f
      raise "Invalid Xbox signature." unless count.in?(1, 2)
      length = 0
      count.times do
        byte = bytes[offset]?.try(&.to_i) ||
               raise "Invalid Xbox signature."
        length = (length << 8) | byte
        offset += 1
      end
      {length, offset}
    end

    private def normalize_integer(value : Bytes) : Bytes
      value = value[1, value.size - 1] if value.size > 32 && value[0] == 0
      raise "Invalid Xbox signature." if value.size > 32
      result = Bytes.new(32, 0_u8)
      value.copy_to(result + (32 - value.size))
      result
    end

    private def ecc_private_blob(x : Bytes, y : Bytes, d : Bytes) : Bytes
      output = IO::Memory.new
      output.write_bytes(0x32534345_u32, IO::ByteFormat::LittleEndian)
      output.write_bytes(32_u32, IO::ByteFormat::LittleEndian)
      output.write(x)
      output.write(y)
      output.write(d)
      output.to_slice
    end

    private def hex_bytes(value : String) : Bytes
      raise "Invalid Xbox device key." unless value.size.even?
      Bytes.new(value.size // 2) do |index|
        value.byte_slice(index * 2, 2).to_u8(16)
      end
    end

    private def credentials_path(root : String) : String
      File.join(root, "auth", "microsoft.json")
    end

    private def write_private_json(path : String, value : JSON::Any) : Nil
      Dir.mkdir_p(File.dirname(path), 0o700)
      temporary = "#{path}.new"
      File.write(temporary, value.to_pretty_json + "\n", perm: 0o600)
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if temporary && File.file?(temporary)
    end

    private def read_json(path : String) : JSON::Any
      JSON.parse(File.read(path))
    rescue
      raise "Microsoft account credentials are missing — sign in again."
    end

    private def required_string(value : JSON::Any, key : String) : String
      optional_string(value, key).presence ||
        raise "Authentication response is missing #{key}."
    end

    private def optional_string(value : JSON::Any, key : String) : String?
      value[key]?.try(&.as_s?)
    end

    private def optional_i64(value : JSON::Any, key : String) : Int64?
      raw = value[key]?
      raw.try(&.as_i64?) || raw.try(&.as_s?).try(&.to_i64?)
    end

    private def openssl : String
      Process.find_executable("openssl") ||
        raise "Bundled OpenSSL tool is missing — reinstall Bedrock Linux GDK."
    end
  end
end
