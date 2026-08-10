//! The envelope in `PROTOCOL.md`: request parsing and the error codes a reply can carry.

use serde_json::{json, Value};

pub const PROTOCOL: u32 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorCode {
    Malformed,
    UnknownCommand,
    UnknownService,
    NotSubscribed,
    BadRequest,
    Unavailable,
    UnknownAccessPoint,
    Rejected,
}

impl ErrorCode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Malformed => "malformed",
            Self::UnknownCommand => "unknown_command",
            Self::UnknownService => "unknown_service",
            Self::NotSubscribed => "not_subscribed",
            Self::BadRequest => "bad_request",
            Self::Unavailable => "unavailable",
            Self::UnknownAccessPoint => "unknown_access_point",
            Self::Rejected => "rejected",
        }
    }
}

#[derive(Debug, Clone)]
pub struct Failure {
    pub code: ErrorCode,
    pub message: String,
}

impl Failure {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }
}

/// A service that could not be reached is `Unavailable`; anything else it refused is
/// `Rejected`. Keeping these apart is what lets a consumer tell a seat without
/// NetworkManager from a passphrase the router would not take.
impl From<koompi_service::Error> for Failure {
    fn from(error: koompi_service::Error) -> Self {
        let code = match error {
            koompi_service::Error::Unavailable(_) => ErrorCode::Unavailable,
            _ => ErrorCode::Rejected,
        };
        Self::new(code, error.to_string())
    }
}

pub type Outcome = Result<(), Failure>;

#[derive(Debug)]
pub struct Request {
    pub id: Option<i64>,
    pub cmd: String,
    body: Value,
}

impl Request {
    /// A line that cannot be read still owes a reply, so the id is recovered where it
    /// survives the parse and the failure is reported rather than returned.
    pub fn parse(line: &str) -> Result<Option<Self>, (Option<i64>, Failure)> {
        if line.trim().is_empty() {
            return Ok(None);
        }

        let body: Value = serde_json::from_str(line)
            .map_err(|e| (None, Failure::new(ErrorCode::Malformed, e.to_string())))?;

        let id = body.get("id").and_then(Value::as_i64);

        let Some(cmd) = body.get("cmd").and_then(Value::as_str) else {
            return Err((
                id,
                Failure::new(ErrorCode::Malformed, "no string \"cmd\""),
            ));
        };

        Ok(Some(Self {
            id,
            cmd: cmd.to_owned(),
            body,
        }))
    }

    pub fn service(&self) -> Result<&str, Failure> {
        self.body
            .get("service")
            .and_then(Value::as_str)
            .ok_or_else(|| Failure::new(ErrorCode::BadRequest, "\"service\" is required"))
    }

    pub fn bool(&self, field: &str) -> Result<bool, Failure> {
        self.body
            .get(field)
            .and_then(Value::as_bool)
            .ok_or_else(|| Failure::new(ErrorCode::BadRequest, missing(field, "a boolean")))
    }

    pub fn str(&self, field: &str) -> Result<&str, Failure> {
        self.body
            .get(field)
            .and_then(Value::as_str)
            .ok_or_else(|| Failure::new(ErrorCode::BadRequest, missing(field, "a string")))
    }

    pub fn opt_str(&self, field: &str) -> Result<Option<&str>, Failure> {
        match self.body.get(field) {
            None | Some(Value::Null) => Ok(None),
            Some(Value::String(text)) => Ok(Some(text)),
            Some(_) => Err(Failure::new(
                ErrorCode::BadRequest,
                missing(field, "a string"),
            )),
        }
    }

    pub fn u64(&self, field: &str) -> Result<u64, Failure> {
        self.body
            .get(field)
            .and_then(Value::as_u64)
            .ok_or_else(|| Failure::new(ErrorCode::BadRequest, missing(field, "a positive integer")))
    }

    pub fn str_list(&self, field: &str) -> Result<Vec<String>, Failure> {
        let items = self
            .body
            .get(field)
            .and_then(Value::as_array)
            .ok_or_else(|| Failure::new(ErrorCode::BadRequest, missing(field, "an array")))?;

        items
            .iter()
            .map(|item| {
                item.as_str()
                    .map(str::to_owned)
                    .ok_or_else(|| Failure::new(ErrorCode::BadRequest, missing(field, "strings")))
            })
            .collect()
    }
}

fn missing(field: &str, want: &str) -> String {
    format!("\"{field}\" must be {want}")
}

pub fn hello(services: &[&str]) -> Value {
    json!({
        "type": "hello",
        "protocol": PROTOCOL,
        "daemon": "koompi-shelld",
        "version": env!("CARGO_PKG_VERSION"),
        "services": services,
    })
}

pub fn state(service: &str, serial: u64, state: Value) -> Value {
    json!({"type": "state", "service": service, "serial": serial, "state": state})
}

pub fn unavailable(service: &str, reason: &str, message: impl Into<String>) -> Value {
    json!({
        "type": "unavailable",
        "service": service,
        "reason": reason,
        "message": message.into(),
    })
}

pub fn reply(id: Option<i64>, outcome: Outcome) -> Value {
    match outcome {
        Ok(()) => json!({"type": "reply", "id": id, "ok": true}),
        Err(failure) => json!({
            "type": "reply",
            "id": id,
            "ok": false,
            "error": failure.code.as_str(),
            "message": failure.message,
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_blank_line_is_not_a_request_and_draws_no_reply() {
        assert!(Request::parse("   ").unwrap().is_none());
    }

    #[test]
    fn an_unreadable_line_still_reports_the_id_where_the_parse_reached_it() {
        let (id, failure) = Request::parse(r#"{"id": 7}"#).unwrap_err();
        assert_eq!(id, Some(7));
        assert_eq!(failure.code, ErrorCode::Malformed);

        let (id, failure) = Request::parse("not json").unwrap_err();
        assert_eq!(id, None);
        assert_eq!(failure.code, ErrorCode::Malformed);
    }

    #[test]
    fn unknown_extra_fields_are_ignored() {
        let request = Request::parse(r#"{"cmd":"ping","nonsense":[1,2],"id":3}"#)
            .unwrap()
            .unwrap();
        assert_eq!(request.cmd, "ping");
        assert_eq!(request.id, Some(3));
    }

    #[test]
    fn an_absent_optional_and_an_explicit_null_read_the_same() {
        let absent = Request::parse(r#"{"cmd":"connect"}"#).unwrap().unwrap();
        let null = Request::parse(r#"{"cmd":"connect","passphrase":null}"#)
            .unwrap()
            .unwrap();
        assert_eq!(absent.opt_str("passphrase").unwrap(), None);
        assert_eq!(null.opt_str("passphrase").unwrap(), None);
    }

    #[test]
    fn a_wrong_typed_argument_is_bad_request_rather_than_a_default() {
        let request = Request::parse(r#"{"cmd":"set_wireless_enabled","enabled":"yes"}"#)
            .unwrap()
            .unwrap();
        assert_eq!(
            request.bool("enabled").unwrap_err().code,
            ErrorCode::BadRequest
        );
    }

    #[test]
    fn an_unavailable_service_is_not_reported_as_a_refusal() {
        let failure = Failure::from(koompi_service::Error::Unavailable("NetworkManager".into()));
        assert_eq!(failure.code, ErrorCode::Unavailable);

        let failure = Failure::from(koompi_service::Error::Protocol("bad reply".into()));
        assert_eq!(failure.code, ErrorCode::Rejected);
    }

    #[test]
    fn a_failed_reply_carries_the_code_and_a_successful_one_does_not() {
        let ok = reply(Some(1), Ok(()));
        assert_eq!(ok["ok"], json!(true));
        assert!(ok.get("error").is_none());

        let failed = reply(None, Err(Failure::new(ErrorCode::NotSubscribed, "power")));
        assert_eq!(failed["id"], Value::Null);
        assert_eq!(failed["error"], json!("not_subscribed"));
    }
}
