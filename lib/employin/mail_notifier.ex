defmodule Employin.MailNotifier do
  import Swoosh.Email

  alias Employin.Mailer

  def login_instructions(email, url, otp) do
    subject = "Login instructions"
    body = get_body(url, otp)
    deliver(email, subject, body)
  end

  defp deliver(recipient, subject, body) do
    name = System.get_env("EMAIL_NAME")
    from = System.get_env("EMAIL_FROM")
    email =
      new()
      |> to(recipient)
      |> from({name, from})
      |> subject(subject)
      |> html_body(body)

    Mailer.deliver(email)
  end

  defp get_body(url, otp) do
    """
    Hi,

    You can login to your account by clicking below:

    <div style="text-align: center;">
      <a href="#{url}" style="font-size: 32px; margin: auto; text-decoration: underline;">Confirm Login</a>
    </div>
    or, copy and paste the OTP:
    <div style="border: 2px solid #000; padding: 10px; text-align: center; max-width: 200px; margin: auto;">
      <p style="font-weight: bold; font-size: 24px;">#{otp}</p>
    </div>
    or, copy and paste the link in your browser:

    <p style="width: 50%; text-decoration: none;">#{url}</p>

    If you didn't create an account with us, please ignore this.
    """
  end
end
