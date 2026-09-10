# Linea Backend

This directory is reserved for the Linea backend.

The backend is developed independently from the iOS client. Communication with the iOS app must happen through the API contract defined in `/API/openapi.yaml`.

The backend stack is not fixed yet. Do not assume a language, framework, database, queue, or hosting provider until the project explicitly chooses them.

Before changing request or response shapes, update `/API/openapi.yaml` first and coordinate the change with the iOS client.

## Role in v1

The intelligence core (state, decisions, nudges, feedback) runs on the device
in `Linea/Core`; the backend is not needed for the first version. Its first
planned responsibility is a thin proxy to a cloud LLM for text explanations
(`POST /v1/explain`), so that provider keys stay on the server and only
derived facts — never raw health samples — leave the device, with explicit
user consent. See `Docs/decisions.md` (ADR-001, ADR-011).
