from bartab.mail import MailError


class FakeMailer:
    """Test double for Mailer: records sends; set `fail` to make send raise MailError."""

    def __init__(self, fail: bool = False) -> None:
        self.sent: list[dict] = []
        self.fail = fail

    def send(self, to, subject, body, attachment=None) -> None:
        if self.fail:
            raise MailError("fake mail failure")
        self.sent.append(
            {"to": list(to), "subject": subject, "body": body, "attachment": attachment}
        )
