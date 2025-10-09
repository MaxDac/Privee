defmodule Bauta.SessionNameProvider do
  @moduledoc """
  This module implements getting a fresh unique session name by checking the
  database in the real implementation, while it will return a constant value
  in the test environment.
  """

  @provider_implementation Application.compile_env(:bauta, :session_name_provider)

  defmodule Behaviour do
    @moduledoc """
    This behaviour abstract the session name provider implementation for
    mocking testing purpose.
    """
    @callback generate_new_available_session_name() :: {:ok, String.t()} | {:error, String.t()}
  end

  @doc """
  Returns a fresh unique session name.
  """
  def generate_new_available_session_name do
    @provider_implementation.generate_new_available_session_name()
  end

  defmodule Impl do
    @moduledoc """
    This module will be used in production, it calls the implementation in the
    `Bauta.Sessions` module to get a unique session name.
    """

    @behaviour Bauta.SessionNameProvider.Behaviour

    alias Bauta.Sessions

    def generate_new_available_session_name do
      {:ok, Sessions.generate_new_available_session_name()}
    end
  end

  defmodule Test do
    @moduledoc """
    This module will be used in the test environment, it returns a constant value.
    """

    @behaviour Bauta.SessionNameProvider.Behaviour

    @mocked_unique_session_name "ed833bb9-4860-4ca4-9bd7-ed7a0093be26"

    @doc """
    Returns the mocked value of the session name used by the module.
    """
    def get_mocked_unique_session_name, do: @mocked_unique_session_name

    def generate_new_available_session_name do
      {:ok, @mocked_unique_session_name}
    end
  end
end
