"""Regression tests for NVIDIA VRAM profiles."""

from __future__ import annotations

import subprocess
import unittest


def profile(
    memory_mib: int,
) -> subprocess.CompletedProcess[str]:
    command = (
        "source offline/lib/gpu.sh; "
        "offline_gpu_profile_for_memory "
        f"{memory_mib}"
    )

    return subprocess.run(
        [
            "bash",
            "-c",
            command,
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


class GPUProfileTests(unittest.TestCase):
    def test_below_6_gib_is_unsupported(
        self,
    ) -> None:
        result = profile(6143)

        self.assertNotEqual(
            result.returncode,
            0,
        )

    def test_6_gib_uses_conservative_profile(
        self,
    ) -> None:
        result = profile(6144)

        self.assertEqual(
            result.returncode,
            0,
        )

        self.assertEqual(
            result.stdout.strip(),
            "conservative|16|0|6144",
        )

    def test_12_gib_uses_conservative_profile(
        self,
    ) -> None:
        result = profile(12288)

        self.assertEqual(
            result.returncode,
            0,
        )

        self.assertEqual(
            result.stdout.strip(),
            "conservative|16|0|12288",
        )

    def test_below_16_gib_stays_conservative(
        self,
    ) -> None:
        result = profile(16383)

        self.assertEqual(
            result.returncode,
            0,
        )

        self.assertEqual(
            result.stdout.strip(),
            "conservative|16|0|16383",
        )

    def test_16_gib_uses_full_profile(
        self,
    ) -> None:
        result = profile(16384)

        self.assertEqual(
            result.returncode,
            0,
        )

        self.assertEqual(
            result.stdout.strip(),
            "full|99|99|16384",
        )


if __name__ == "__main__":
    unittest.main()
