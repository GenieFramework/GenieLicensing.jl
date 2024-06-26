module GenieLicensing

using HTTP, JSON, Logging, Retry

const LICENSE_API = get!(ENV, "GENIE_LICENSE_API", "https://licensing.hosting.genieframework.com") # no trailing slash
const USER_EMAIL = get!(ENV, "GENIE_USER_EMAIL", "__UNKNWON__@genieframework.com")
const USER_FULL_NAME = get!(ENV, "GENIE_USER_FULL_NAME", "Unknown User")
const ORIGIN = get!(ENV, "GENIE_ORIGIN", "Unknown")
const METADATA = get!(ENV, "GENIE_METADATA", "")
const FAILED_SESSION_ID = "__failed_session_id__"

@inline function is_failed_session()
  return ENV["GENIE_SESSION"] == FAILED_SESSION_ID
end

function start_session()
  session_data = try
    @repeat 10 try
      HTTP.post( LICENSE_API * "/sessions/create";
                body = Dict(
                  "email" => USER_EMAIL,
                  "name"  => USER_FULL_NAME,
                  "origin" => ORIGIN,
                  "metadata" => Dict("app_url" => METADATA) |> JSON.json
                ),
                status_exception = true
              )
    catch ex
      @warn("Failed to start session. Retrying. $ex")
      @delay_retry if true end
    end
  catch ex
    @warn("Failed to start session. Giving up. $ex")
    ENV["GENIE_SESSION"] = FAILED_SESSION_ID

    return
  end

  if session_data.status == 200
    try
      ENV["GENIE_SESSION"] = (session_data.body |> String |> JSON.parse)["session"]["id"]
    catch ex
      @warn("Failed to parse session data: $ex")
      ENV["GENIE_SESSION"] = FAILED_SESSION_ID
    end
  end

  ENV["GENIE_SESSION"]
end

function log(origin, type, payload::AbstractDict)
  if is_failed_session()
    @warn("No session found, skipping logging")
    return
  end

  try
    HTTP.post(LICENSE_API * "/actions";
              body = Dict(
                "session_hash" => get(ENV, "GENIE_SESSION", FAILED_SESSION_ID),
                "origin" => origin,
                "type" => type,
                "metadata" => payload |> JSON.json
              ),
              status_exception = false
    )
  catch ex
    @warn("Failed to log action: $ex")
  end

  nothing
end

function quotas()
  if is_failed_session()
    return Dict()
  end

  quotas_data = try
    HTTP.get(LICENSE_API * "/sessions/" * ENV["GENIE_SESSION"] * "/quotas"; status_exception = false)
  catch ex
    @warn("Failed to get quotas: $ex")
    return Dict()
  end

  if quotas_data.status != 200
    return Dict()
  end

  try
    (quotas_data.body |> String |> JSON.parse)["quotas"]
  catch ex
    @warn("Failed to parse quotas data: $ex")
    return Dict()
  end
end

function __init__() #TODO: uncouple this
  if get(ENV, "JULIAHUB_USEREMAIL", "") != ""
    ENV["GENIE_USER_EMAIL"] = ENV["JULIAHUB_USEREMAIL"]
  end
  if get(ENV, "JULIAHUB_USER_FULL_NAME", "") != ""
    ENV["GENIE_USER_FULL_NAME"] = ENV["JULIAHUB_USER_FULL_NAME"]
  end
  if get(ENV, "JULIA_PKG_SERVER", "") != ""
    ENV["GENIE_ORIGIN"] = ENV["JULIA_PKG_SERVER"]
  end
  if get(ENV, "JULIAHUB_APP_URL", "") != ""
    ENV["GENIE_METADATA"] = ENV["JULIAHUB_APP_URL"]
  end
end



end
