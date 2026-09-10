//
//  LineaBackend.swift
//  Linea
//
//  The seam between Linea's UI and a future web backend.
//
//  In v1 the backend takes part in nothing: decisions are made on the device
//  (Linea/Core) and texts come from the rule-based explainer or the on-device
//  model. The first planned endpoint is a proxy for a cloud LLM, so provider
//  keys stay on the server and only derived facts — never raw health samples —
//  would leave the device, with explicit consent. See Docs/decisions.md
//  (ADR-001, ADR-011) and API/openapi.yaml.
//
//  No production endpoints, auth or payload shapes are invented here.
//

import Foundation

protocol LineaBackend: Sendable {
    /// Rephrases an already-made decision. The request carries typed facts,
    /// not measurements; the response is text only.
    func explain(_ request: ExplanationRequest) async throws -> Explanation
}
