defmodule PriveeWeb.App.InfoControllerTest do
  # Not async: some tests change the `:instance` application env.
  use PriveeWeb.ConnCase, async: false

  setup do
    previous = Application.get_env(:privee_web, :instance)
    on_exit(fn -> Application.put_env(:privee_web, :instance, previous) end)
  end

  test "GET /api/app/info describes the instance without authentication" do
    conn = get(json_conn(), ~p"/api/app/info")

    assert %{
             "service" => "privee",
             "api_version" => 1,
             "version" => version,
             "name" => nil,
             "source_url" => "https://github.com/MaxDac/Privee"
           } = json_response(conn, 200)

    assert version == to_string(Application.spec(:privee_web, :vsn))
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "GET /api/app/info reports the configured name and source URL" do
    Application.put_env(:privee_web, :instance,
      name: "  Family server ",
      source_url: "https://git.example.com/me/privee-fork"
    )

    assert %{"name" => "Family server", "source_url" => "https://git.example.com/me/privee-fork"} =
             json_response(get(json_conn(), ~p"/api/app/info"), 200)
  end

  test "GET /api/app/info falls back to defaults for blank values" do
    Application.put_env(:privee_web, :instance, name: "", source_url: " ")

    assert %{"name" => nil, "source_url" => "https://github.com/MaxDac/Privee"} =
             json_response(get(json_conn(), ~p"/api/app/info"), 200)
  end

  defp json_conn, do: put_req_header(build_conn(), "accept", "application/json")
end
