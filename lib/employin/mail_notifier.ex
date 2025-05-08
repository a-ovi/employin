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
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Login Instructions</title>
    </head>
    <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333333; max-width: 600px; margin: 0 auto; padding: 20px;">
      <div style="border-bottom: 1px solid #eeeeee; padding-bottom: 20px; margin-bottom: 20px;">
        <h1 style="color: #444444; font-size: 24px; margin-top: 0;">Login Instructions</h1>
      </div>

      <div style="margin-bottom: 30px;">
        <p>Hi there,</p>
        <p>You can login to your account using one of the methods below:</p>

        <div style="background-color: #f7f7f7; border-radius: 6px; padding: 20px; margin: 25px 0;">
          <a href="#{url}" style="display: block; background-color: #4a7aff; color: white; text-align: center; padding: 14px 20px; text-decoration: none; border-radius: 4px; font-weight: bold;">Confirm Login</a>
        </div>

        <p style="font-weight: bold; margin-bottom: 5px;">Or use this one-time password:</p>
        <div style="background-color: #f7f7f7; border: 1px solid #dddddd; border-radius: 4px; padding: 12px; text-align: center; margin-bottom: 20px;">
          <p style="font-family: monospace; font-size: 20px; font-weight: bold; letter-spacing: 2px; margin: 0;">#{otp}</p>
        </div>

        <p style="font-weight: bold; margin-bottom: 5px;">Or copy and paste this link in your browser:</p>
        <p style="word-break: break-all; background-color: #f7f7f7; border: 1px solid #dddddd; border-radius: 4px; padding: 10px; font-size: 14px;">#{url}</p>
      </div>

      <div style="color: #777777; font-size: 13px; border-top: 1px solid #eeeeee; padding-top: 20px;">
        <p>If you didn't create an account with us, please ignore this email.</p>
        <p>This is an automated message, please do not reply.</p>
      </div>
    </body>
    </html>
    """
  end
end
