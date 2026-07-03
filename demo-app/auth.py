"""Demo authentication gate for the RCM analytics demo app.

DEMO ONLY. This is a single shared-password gate driven by one environment
variable — enough to show the pattern (constant-time comparison, session
state, no secrets in code) without reproducing a production auth system.
"""
from __future__ import annotations

import hmac
import os

import streamlit as st

_SESSION_KEY = "demo_authenticated"


def _expected_password() -> str:
    """Read the demo password from the environment. Empty string disables auth."""
    return os.getenv("DEMO_PASSWORD", "")


def is_authenticated() -> bool:
    """Return True when auth is disabled or the session has already passed the gate."""
    if not _expected_password():
        return True
    return bool(st.session_state.get(_SESSION_KEY, False))


def render_login() -> None:
    """Render the login form and stop the script until the password matches."""
    st.title("RCM Analytics Demo")
    st.caption("Demonstration app — synthetic data only.")

    with st.form("demo_login"):
        supplied = st.text_input("Demo password", type="password")
        submitted = st.form_submit_button("Enter")

    if submitted:
        if hmac.compare_digest(supplied, _expected_password()):
            st.session_state[_SESSION_KEY] = True
            st.rerun()
        st.error("Incorrect password.")

    st.stop()


def require_auth() -> None:
    """Gate the rest of the page: show the login form unless authenticated."""
    if not is_authenticated():
        render_login()
