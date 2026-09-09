# Linea Backend

This directory is reserved for the Linea backend.

The backend is developed independently from the iOS client. Communication with the iOS app must happen through the API contract defined in `/API/openapi.yaml`.

The backend stack is not fixed yet. Do not assume a language, framework, database, queue, or hosting provider until the project explicitly chooses them.

Before changing request or response shapes, update `/API/openapi.yaml` first and coordinate the change with the iOS client.
