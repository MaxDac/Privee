defmodule PriveeWeb.ClientTexts do
  @moduledoc "The browser client uses the same Gettext catalogs as server-rendered UI."
  use Gettext, backend: PriveeWeb.Gettext

  def translations(locale) do
    Gettext.with_locale(PriveeWeb.Gettext, locale, fn ->
      %{
        undecryptable: gettext("This message could not be decrypted."),
        unavailable: gettext("Sent from another device."),
        noPeerKeys:
          gettext("Your contact has not set up encryption yet. Try again once they are online."),
        sendFailed: gettext("The message could not be sent. Please try again."),
        sendQueued:
          gettext("The message could not be delivered yet. It will be sent automatically."),
        identityChanged:
          gettext(
            "Your contact's security code changed. They may have reset their device, or someone may be intercepting the conversation. Verify the safety number with them before continuing."
          ),
        superseded:
          gettext(
            "Encryption for this session was reset on another device, so this device can no longer send or receive messages."
          ),
        needsReset:
          gettext(
            "This device has no encryption keys for this session. Reset the encryption identity to continue; messages sent to your previous device will not be readable here."
          ),
        unsupported:
          gettext(
            "This browser does not support the features required for end-to-end encryption (Web Locks). Please use an up-to-date browser."
          ),
        failedToStart: gettext("Encryption could not be initialized. Please reload the page."),
        earlier: gettext("Earlier on this device"),
        confirmClear: gettext("Delete the local history of this conversation from this device?"),
        confirmForget:
          gettext(
            "Delete all encryption keys and history of this session from this device? You will need to reset encryption to chat again."
          ),
        confirmReset:
          gettext(
            "Reset the encryption identity of this session? Your contacts will be asked to verify your new safety number."
          ),
        acceptIdentity: gettext("Accept new security code"),
        resetIdentity: gettext("Reset encryption identity"),
        exchangeFirst: gettext("Exchange a message first to compare safety numbers."),
        compareSafety:
          gettext(
            "Compare this number with your contact, in person or over another channel. If it matches, the conversation is end-to-end encrypted."
          ),
        close: gettext("Close"),
        sessionCopied: gettext("Session copied"),
        urlCopied: gettext("Url copied"),
        copyFailed: gettext("Could not copy to the clipboard."),
        notificationTitle: gettext("Privee - Text received"),
        notificationBody: gettext("New message received"),
        notificationsUnsupported: gettext("This browser does not support notifications."),
        messagePlaceholder: gettext("Write your message here"),
        messageLabel: gettext("Message"),
        send: gettext("Send")
      }
    end)
  end
end
