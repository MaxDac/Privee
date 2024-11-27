defmodule Privee.Chats do
  @moduledoc """
  Acts as a wrapper around Erlang ETS tables, to store the chats.
  The purpose of this module is to offer a clean set of API to read and write chats,
  and to automatically delete a chat when its expiration date will be reached.
  """

  use GenServer

  alias Privee.Sessions.Message

  @chat_table_name :chat_messages

  @impl true
  @doc """
  Creates the database table, returning the table name.
  """
  def init(_opts) do
    _ = create_database()
    {:ok, []}
  end

  def create_database(_opts \\ []) do
    if :ets.whereis(@chat_table_name) == :undefined do
      :ets.new(@chat_table_name, [:bag, :protected, :named_table])
    end
  end

  @doc """
  Creates a message in the table. The message will be created twice, both for the
  sender and for the receiver. This way, the lookup will be quicker, as it will
  require only one match.
  """
  @impl true
  def handle_cast({:create_message, %Message{from: from, to: to} = message}, state) do
    timestamp = :os.system_time()
    :ets.insert(@chat_table_name, {from, to, message, timestamp})
    :ets.insert(@chat_table_name, {to, from, message, timestamp})
    {:noreply, state}
  end

  @doc """
  Gets the message between the receiver and the sender by matching the message keys
  and the secondary key specified at the moment of storing the message in ETS.
  """
  @impl true
  def handle_call({:get_messages, current_session_id, chat_session_id}, _from, state) do
    messages =
      :ets.match(@chat_table_name, {current_session_id, chat_session_id, :"$3", :_})
      |> List.flatten()

    {:reply, messages, state}
  end

  #
  # API
  #

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a message in the table. The message will be created twice, both for the
  sender and for the receiver. This way, the lookup will be quicker, as it will
  require only one match.
  """
  def create_message(message) do
    GenServer.cast(__MODULE__, {:create_message, message})
  end

  @doc """
  Gets the message between the receiver and the sender by matching the message keys
  and the secondary key specified at the moment of storing the message in ETS.
  """
  @spec get_messages(
          current_session_id :: non_neg_integer(),
          chat_session_id :: non_neg_integer()
        ) ::
          list(Message.t())
  def get_messages(current_session_id, chat_session_id) do
    GenServer.call(__MODULE__, {:get_messages, current_session_id, chat_session_id})
  end
end
