import sys
from pathlib import Path

import numpy as np
import onnx
from onnx import TensorProto, helper
import onnxruntime as ort

print("Python:", sys.version.replace("\n", " "))
print("ONNX Runtime:", ort.__version__)
print("Providers:", ort.get_available_providers())

model_path = Path("/tmp/lit004_ort_add_test.onnx")

x = helper.make_tensor_value_info("X", TensorProto.FLOAT, [1])
y = helper.make_tensor_value_info("Y", TensorProto.FLOAT, [1])
z = helper.make_tensor_value_info("Z", TensorProto.FLOAT, [1])
node = helper.make_node("Add", ["X", "Y"], ["Z"])
graph = helper.make_graph([node], "lit004_add_test", [x, y], [z])
model = helper.make_model(
    graph,
    producer_name="lit004-build-pack",
    opset_imports=[helper.make_opsetid("", 13)],
)
# ORT 1.16.3 understands this IR version.
model.ir_version = 8
onnx.save(model, model_path)

session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
out = session.run(
    None,
    {
        "X": np.array([1.0], dtype=np.float32),
        "Y": np.array([2.0], dtype=np.float32),
    },
)

value = float(out[0][0])
print("Inference result:", value)
if value != 3.0:
    raise SystemExit(f"Unexpected inference result: {value}")

print("RESULT: PASS")
