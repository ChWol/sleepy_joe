#!/usr/bin/env python3
"""
generate_model.py – SleepyJoe Updatable CoreML Model Generator

Generates an updatable 2-layer MLP classifier for on-device micro-sleep detection.
Architecture: Input(16) → Dense(16, ReLU) → Dense(2, Softmax)

The 16 input features are extracted from 5-second accelerometer + pitch windows
using Apple's vDSP framework (see FeatureExtractor.swift).

Only the output layer (fc2) is marked as updatable for on-device fine-tuning
via MLUpdateTask, keeping the hidden representation frozen.

Usage:
    pip install coremltools numpy
    python3 scripts/generate_model.py

Output:
    SleepyJoe Watch App/ML/SleepyClassifier.mlmodel
"""

import os
import sys
import numpy as np

try:
    import coremltools as ct
    from coremltools.models.neural_network import NeuralNetworkBuilder, AdamParams
    from coremltools.models import datatypes
except ImportError:
    print("ERROR: coremltools not installed. Run: pip install coremltools numpy")
    sys.exit(1)


def generate_updatable_mlp():
    """Generate an updatable 2-layer MLP for sleep/awake classification."""
    
    # ─── Architecture Parameters ───
    INPUT_DIM = 16   # 16 vDSP-extracted physiological features
    HIDDEN_DIM = 16  # Single hidden layer
    OUTPUT_DIM = 2   # Binary: "awake" vs "sleep"
    CLASSES = ["awake", "sleep"]
    
    # ─── I/O Specifications ───
    # For a neural network classifier, specify input and output features.
    # The output should be the softmax probabilities array.
    # coremltools will add the classLabel output automatically via set_class_labels().
    input_features = [("features", datatypes.Array(INPUT_DIM))]
    output_features = [("probabilities", datatypes.Array(OUTPUT_DIM))]
    
    # ─── Build Neural Network ───
    builder = NeuralNetworkBuilder(
        input_features, output_features, mode="classifier"
    )
    
    # Hidden Layer 1: Dense(16 → 16) + ReLU
    # Xavier initialization for stable convergence on small datasets
    np.random.seed(42)  # Reproducible weights
    w1 = np.random.randn(HIDDEN_DIM, INPUT_DIM).astype(np.float32) * np.sqrt(
        2.0 / INPUT_DIM
    )
    b1 = np.zeros(HIDDEN_DIM, dtype=np.float32)
    
    builder.add_inner_product(
        name="fc1",
        W=w1,
        b=b1,
        input_channels=INPUT_DIM,
        output_channels=HIDDEN_DIM,
        has_bias=True,
        input_name="features",
        output_name="fc1_out",
    )
    builder.add_activation(
        name="relu1",
        non_linearity="RELU",
        input_name="fc1_out",
        output_name="relu1_out",
    )
    
    # Output Layer: Dense(16 → 2) + Softmax
    w2 = np.random.randn(OUTPUT_DIM, HIDDEN_DIM).astype(np.float32) * np.sqrt(
        2.0 / HIDDEN_DIM
    )
    b2 = np.zeros(OUTPUT_DIM, dtype=np.float32)
    
    builder.add_inner_product(
        name="fc2",
        W=w2,
        b=b2,
        input_channels=HIDDEN_DIM,
        output_channels=OUTPUT_DIM,
        has_bias=True,
        input_name="relu1_out",
        output_name="raw_logits",
    )
    builder.add_softmax(
        name="softmax", input_name="raw_logits", output_name="probabilities"
    )
    
    # ─── Classifier Labels ───
    builder.set_class_labels(CLASSES)
    builder.spec.description.predictedFeatureName = "classLabel"
    builder.spec.description.predictedProbabilitiesName = "probabilities"
    
    # ─── Mark Output Layer as Updatable ───
    # Only fc2 (classifier head) is fine-tuned on-device.
    # fc1 (feature representation) stays frozen.
    builder.make_updatable(["fc2"])
    
    # ─── Loss Function: Categorical Cross-Entropy ───
    builder.set_categorical_cross_entropy_loss(
        name="cross_entropy_loss", input="probabilities"
    )
    
    # ─── Optimizer: Adam ───
    # Conservative learning rate for few-shot on-device training
    builder.set_adam_optimizer(
        AdamParams(
            lr=0.005,   # Conservative LR prevents gradient explosion on <30 samples
            batch=8,    # Small batch for quick updates
            beta1=0.9,
            beta2=0.999,
            eps=1e-8,
        )
    )
    
    # ─── Epoch Configuration ───
    # Default: 15 epochs, allowed values for on-device tuning
    builder.set_epochs(15, allowed_set=[5, 10, 15, 20, 30, 50])
    
    # ─── Enable Updatability ───
    builder.spec.isUpdatable = True
    builder.spec.specificationVersion = 4  # Required for updatable models
    
    # ─── Model Metadata ───
    builder.spec.description.metadata.author = "SleepyJoe Team"
    builder.spec.description.metadata.shortDescription = (
        "Updatable 2-layer MLP for on-device micro-sleep detection. "
        "Input: 16 vDSP-extracted features from 5s accelerometer window. "
        "Output: sleep/awake classification with probability."
    )
    builder.spec.description.metadata.versionString = "1.0.0"
    
    # ─── Input/Output Descriptions ───
    builder.spec.description.input[0].shortDescription = (
        "16 physiological features: means(3), variances(3), totalJitter(1), "
        "SMA(1), peakToPeak(3), pitch stats(3), ZCR(1), peakEnergy(1)"
    )
    
    return ct.models.MLModel(builder.spec)


def main():
    print("=" * 60)
    print("SleepyJoe – Updatable CoreML Model Generator")
    print("=" * 60)
    
    # Generate model
    print("\n[1/3] Building updatable 2-layer MLP architecture...")
    print("      Input(16) → Dense(16, ReLU) → Dense(2, Softmax)")
    model = generate_updatable_mlp()
    print("      ✓ Architecture built successfully")
    
    # Output path
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    output_dir = os.path.join(project_root, "SleepyJoe Watch App", "ML")
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, "SleepyClassifier.mlmodel")
    
    # Save model
    print(f"\n[2/3] Saving model to: {output_path}")
    model.save(output_path)
    
    # Validate
    file_size = os.path.getsize(output_path)
    print(f"      ✓ Model saved ({file_size:,} bytes)")
    
    # Summary
    print(f"\n[3/3] Model Summary:")
    print(f"      - Parameters: ~{16 * 16 + 16 + 2 * 16 + 2} (fc1: {16*16+16}, fc2: {2*16+2})")
    print(f"      - Updatable layers: fc2 only (classifier head)")
    print(f"      - Optimizer: Adam (lr=0.005, batch=8)")
    print(f"      - Loss: Categorical Cross-Entropy")
    print(f"      - Default epochs: 15")
    print(f"      - Classes: ['awake', 'sleep']")
    print(f"      - Spec version: 4 (updatable)")
    print(f"\n{'=' * 60}")
    print("Done! Add SleepyClassifier.mlmodel to the Xcode project.")
    print("=" * 60)


if __name__ == "__main__":
    main()
