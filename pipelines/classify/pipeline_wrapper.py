"""Diagnostic domain/risk decision endpoint."""

from hayhooks import BasePipelineWrapper

from chatbot_app.domain import DomainClassifier
from chatbot_app.policy import DomainPolicy


class PipelineWrapper(BasePipelineWrapper):
    """Expose raw scores and final policy decision."""

    skip_mcp = True

    def setup(self) -> None:
        self.classifier = DomainClassifier()
        self.policy = DomainPolicy()

    def run_api(
        self,
        query: str,
    ) -> dict[str, object]:
        scores = self.classifier.classify(query)
        decision = self.policy.decide(query, scores)

        return {
            "decision": decision.to_dict(),
            "raw": {
                "best_label": scores.best_label,
                "confidence": scores.confidence,
                "margin": scores.margin,
                "risk_score": scores.risk_score,
                "class_scores": scores.class_scores,
            },
        }
