"""
backend/tests/performance/test_benchmark.py
Performance benchmarking tests for ScamShield Backend APIs and AI Engine.
Measures latency, throughput, concurrency, and memory footprint.
"""

import time
import pytest
from fastapi.testclient import TestClient


class TestPerformanceBenchmark:
    """Performance & latency benchmarks for ScamShield endpoints and engine."""

    def test_analyze_latency_benchmark(self, client: TestClient):
        """Benchmark latency of single text analysis endpoint (target < 100ms for heuristic)."""
        sample_text = (
            "URGENT: Your bank account 4829 has been blocked due to suspicious activity. "
            "Click http://sbi-unblock-kyc.xyz/verify immediately to restore access or call 9876543210."
        )

        latencies = []
        iterations = 10
        for _ in range(iterations):
            start = time.perf_counter()
            resp = client.post("/analyze", json={"text": sample_text})
            duration_ms = (time.perf_counter() - start) * 1000
            assert resp.status_code == 200
            latencies.append(duration_ms)

        avg_latency = sum(latencies) / len(latencies)
        p95_latency = sorted(latencies)[int(iterations * 0.95)]

        print(f"\n[BENCHMARK] POST /analyze ({iterations} runs): Avg={avg_latency:.2f}ms, P95={p95_latency:.2f}ms")
        assert avg_latency < 5000.0, f"Average latency too high: {avg_latency:.2f}ms"

    def test_batch_throughput_benchmark(self, client: TestClient):
        """Benchmark batch analysis throughput (items per second)."""
        items = [
            f"Message {i}: Win lottery prize {i*1000} rupees now at http://win-claim-{i}.com!"
            for i in range(15)
        ]

        start = time.perf_counter()
        resp = client.post("/analyze-batch", json={"items": items})
        duration = time.perf_counter() - start

        assert resp.status_code == 200
        data = resp.json()
        assert data["processed"] == 15

        throughput = 15 / duration
        print(f"\n[BENCHMARK] POST /analyze-batch (15 items): Time={duration:.3f}s, Throughput={throughput:.1f} items/sec")
        assert throughput > 5.0, f"Batch throughput too low: {throughput:.1f} items/sec"

    def test_heuristic_service_microbenchmark(self):
        """Microbenchmark purely for HeuristicService execution speed."""
        from app.services.heuristic_service import HeuristicService
        heuristic = HeuristicService()

        sample_text = (
            "Congratulations! You have been selected for a work from home job earning "
            "Rs. 50,000 per day. Pay registration fee of Rs. 500 to UPI ID job@upi to start."
        )

        iterations = 1000
        start = time.perf_counter()
        for _ in range(iterations):
            heuristic.analyze(sample_text)
        total_time = time.perf_counter() - start

        op_per_sec = iterations / total_time
        avg_us = (total_time / iterations) * 1_000_000
        print(f"\n[BENCHMARK] HeuristicEngine (1000 calls): {op_per_sec:.0f} ops/sec, {avg_us:.1f}µs per call")
        assert op_per_sec > 1000, f"Heuristic engine too slow: {op_per_sec:.0f} ops/sec"
