"""
Tests for elementwise operations using PyPTO frontend.

Tests tile-level binary operations like add, sub, mul, div.
These tests use the simplified pattern where orchestration is auto-generated.
"""

import sys
from pathlib import Path
from typing import Any, List

import numpy as np
import pytest

from pto_test.core import environment
from pto_test.core.test_case import DataType, PTOTestCase, TensorSpec

# Add pypto to path
_PYPTO_PYTHON = environment.get_pypto_python_path()
if _PYPTO_PYTHON is not None and _PYPTO_PYTHON.exists() and str(_PYPTO_PYTHON) not in sys.path:
    sys.path.insert(0, str(_PYPTO_PYTHON))


class TestTileAdd(PTOTestCase):
    """Test case for tile element-wise addition.

    This test case demonstrates the simplified pattern:
    - Just implement incore function in get_program() and compute_expected()
    - Orchestration function will be auto-generated

    Note: PyPTO requires shape dimensions to be compile-time constants in type
    annotations. The shape is fixed at 128x128 for this test case.
    """

    ROWS = 128
    COLS = 128

    def __init__(self, rows: int = 128, cols: int = 128, **kwargs):
        super().__init__(**kwargs)
        self.rows = rows
        self.cols = cols

    def get_name(self) -> str:
        return f"tile_add_{self.rows}x{self.cols}"

    def define_tensors(self) -> List[TensorSpec]:
        return [
            TensorSpec("a", [self.rows, self.cols], DataType.FP32, init_value=2.0),
            TensorSpec("b", [self.rows, self.cols], DataType.FP32, init_value=3.0),
            TensorSpec("c", [self.rows, self.cols], DataType.FP32, is_output=True),
        ]

    def get_program(self) -> Any:
        import pypto.language as pl

        # PyPTO parser requires constant shape dimensions in type annotations.
        # Use literal values throughout.

        @pl.program
        class TileAddProgram:
            @pl.function
            def tile_add(
                self,
                a: pl.Tensor[[128, 128], pl.FP32],
                b: pl.Tensor[[128, 128], pl.FP32],
                c: pl.Tensor[[128, 128], pl.FP32],
            ) -> pl.Tensor[[128, 128], pl.FP32]:
                tile_a = pl.op.block.load(a, 0, 0, 128, 128)
                tile_b = pl.op.block.load(b, 0, 0, 128, 128)
                tile_c = pl.op.block.add(tile_a, tile_b)
                out_c = pl.op.block.store(tile_c, 0, 0, 128, 128, c)
                return out_c

            @pl.function(type=pl.FunctionType.Orchestration)
            def orchestrator(
                self, a: pl.Tensor[[128, 128], pl.FP32], b: pl.Tensor[[128, 128], pl.FP32]
            ) -> pl.Tensor[[128, 128], pl.FP32]:
                out_c = self.tile_add(a, b)
                return out_c

        return TileAddProgram

    def compute_expected(self, tensors, params=None):
        tensors["c"][:] = tensors["a"] + tensors["b"]


class TestTileMul(PTOTestCase):
    """Test case for tile element-wise multiplication."""

    def __init__(self, rows: int = 128, cols: int = 128, **kwargs):
        super().__init__(**kwargs)
        self.rows = rows
        self.cols = cols

    def get_name(self) -> str:
        return f"tile_mul_{self.rows}x{self.cols}"

    def define_tensors(self) -> List[TensorSpec]:
        return [
            # Method 1: Use Callable to generate random data (different on each run)
            TensorSpec(
                "a",
                [self.rows, self.cols],
                DataType.FP32,
                init_value=lambda shape: np.random.randn(*shape),
            ),
            # Method 2: Use scalar value (recommended - simple and serializable)
            TensorSpec("b", [self.rows, self.cols], DataType.FP32, init_value=3.0),
            # For other methods, see TestCustomArrayInit class examples:
            # - Small arrays can use np.array([[...]])
            # - Identity matrix: np.eye(n)
            # - Diagonal matrix: np.diag([...])
            # Output tensor: automatically zero-initialized
            TensorSpec("c", [self.rows, self.cols], DataType.FP32, is_output=True),
        ]

    def get_program(self) -> Any:
        import pypto.language as pl

        @pl.program
        class TileMulProgram:
            @pl.function
            def tile_mul(
                self,
                a: pl.Tensor[[128, 128], pl.FP32],
                b: pl.Tensor[[128, 128], pl.FP32],
                c: pl.Tensor[[128, 128], pl.FP32],
            ) -> pl.Tensor[[128, 128], pl.FP32]:
                tile_a = pl.op.block.load(a, 0, 0, 128, 128)
                tile_b = pl.op.block.load(b, 0, 0, 128, 128)
                tile_c = pl.op.block.mul(tile_a, tile_b)
                out_c = pl.op.block.store(tile_c, 0, 0, 128, 128, c)
                return out_c

            @pl.function(type=pl.FunctionType.Orchestration)
            def orchestrator(
                self, a: pl.Tensor[[128, 128], pl.FP32], b: pl.Tensor[[128, 128], pl.FP32]
            ) -> pl.Tensor[[128, 128], pl.FP32]:
                out_c = self.tile_mul(a, b)
                return out_c

        return TileMulProgram

    def compute_expected(self, tensors, params=None):
        tensors["c"][:] = tensors["a"] * tensors["b"]


class TestTileAddWithPTOAS(TestTileAdd):
    """Test tile add with PTOAS optimization strategy.

    This demonstrates how to use a custom optimization strategy.
    """

    def get_strategy(self):
        from pypto.ir.pass_manager import OptimizationStrategy

        return OptimizationStrategy.PTOAS

    def get_name(self) -> str:
        return f"tile_add_ptoas_{self.rows}x{self.cols}"


class TestCustomArrayInit(PTOTestCase):
    """Test case demonstrating custom array initialization patterns."""

    def get_name(self) -> str:
        return "custom_array_init"

    def define_tensors(self) -> List[TensorSpec]:
        return [
            # Small array: custom values (will be serialized)
            TensorSpec(
                "small",
                [3, 3],
                DataType.FP32,
                init_value=np.array([[1, 2, 3], [4, 5, 6], [7, 8, 9]], dtype=np.float32),
            ),
            # Identity matrix
            TensorSpec("identity", [4, 4], DataType.FP32, init_value=np.eye(4, dtype=np.float32)),
            # Constant array (optimized to np.full)
            TensorSpec("constant", [5, 5], DataType.FP32, init_value=np.ones((5, 5)) * 3.14),
            # Diagonal matrix (small arrays will be serialized)
            TensorSpec(
                "diagonal", [3, 3], DataType.FP32, init_value=np.diag([1, 2, 3]).astype(np.float32)
            ),
            # Output
            TensorSpec("out", [3, 3], DataType.FP32, is_output=True),
        ]

    def get_program(self) -> Any:
        # Placeholder - this test is just for demonstrating array initialization
        return None

    def compute_expected(self, tensors, params=None):
        # Simple example: copy small array to output
        tensors["out"][:] = tensors["small"][:3, :3]


# =============================================================================
# pytest test functions
# =============================================================================


class TestElementwiseOperations:
    """Test suite for elementwise operations."""

    @pytest.mark.parametrize("rows,cols", [(64, 64), (128, 128)])
    def test_tile_add_shapes(self, test_runner, rows, cols):
        """Test tile addition with various shapes."""
        test_case = TestTileAdd(rows=rows, cols=cols)
        result = test_runner.run(test_case)
        assert result.passed, f"Test failed for {rows}x{cols}: {result.error}"

    @pytest.mark.parametrize("rows,cols", [(64, 64), (128, 128)])
    def test_tile_mul_shapes(self, test_runner, rows, cols):
        """Test tile multiplication with various shapes."""
        test_case = TestTileMul(rows=rows, cols=cols)
        result = test_runner.run(test_case)
        assert result.passed, f"Test failed for {rows}x{cols}: {result.error}"

    def test_tile_add_ptoas_strategy(self, test_runner):
        """Test tile addition with PTOAS optimization strategy."""
        test_case = TestTileAddWithPTOAS(rows=128, cols=128)
        result = test_runner.run(test_case)
        assert result.passed, f"Test failed: {result.error}"
