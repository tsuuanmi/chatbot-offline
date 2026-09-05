"""Minimal Haystack pipeline used to validate the application runtime."""

from haystack import Pipeline
from haystack.components.builders import PromptBuilder
from hayhooks import BasePipelineWrapper


class PipelineWrapper(BasePipelineWrapper):
    """Minimal pipeline with no external dependencies."""

    skip_mcp = True

    def setup(self) -> None:
        pipeline = Pipeline()

        pipeline.add_component(
            "formatter",
            PromptBuilder(
                template="M1 OK | {{ message }}",
            ),
        )

        self.pipeline = pipeline

    def run_api(self, message: str = "ping") -> dict[str, str]:
        result = self.pipeline.run(
            {
                "formatter": {
                    "message": message,
                }
            }
        )

        return {
            "response": result["formatter"]["prompt"],
        }
