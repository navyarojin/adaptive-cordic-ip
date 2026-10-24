"""Frozen trained Banknote Authentication model (4 -> 4 tanh -> 1 sigmoid).

Requires NumPy. No training, downloads, or Phase2 dependencies.
Feature order: wavelet variance, skewness, kurtosis, image entropy.
Outputs retain the dataset's numeric class labels (0 or 1).
Default inference preserves Q7 input/weight/hidden rounding and Q14 biases,
with mathematical tanh/sigmoid; it is not a bit-exact RTL CORDIC simulator.
Use quantized=False for the original floating-point trained parameters.

Example:
    from model import predict, predict_proba
    probabilities = predict_proba([[3.6216, 8.6661, -2.8073, -0.44699]])
    labels = predict([[3.6216, 8.6661, -2.8073, -0.44699]])

CLI: python model.py 3.6216 8.6661 -2.8073 -0.44699
"""
import argparse
import numpy as np

MODEL = {'dataset': 'UCI Banknote Authentication', 'citation': 'Lohweg, V. (2012). Banknote Authentication. UCI Machine Learning Repository. https://doi.org/10.24432/C55P57', 'license': 'CC BY 4.0', 'data_sha256': 'd0539aaed2139ba7a587b3e34fb345ce503ff7d5d33dbf9912d8e195ce425cb9', 'architecture': '4 inputs -> 4 tanh -> 1 sigmoid; output layer padded to 4 lanes', 'selected': {'seed': 23, 'epoch': 640, 'validation_loss': 0.24495921701412873, 'validation_accuracy': 0.9776951672862454}, 'normalization_mean': [0.4028714345297034, 2.0990764820757435, 1.3664534936757449, -1.2262218528465343], 'normalization_scale': [7.836812036347056, 16.60734366534289, 17.093417375078165, 7.7073454180562795], 'float_parameters': [[[0.9921875, 0.9921875, 0.9921875, -0.9921875], [0.9921875, 0.9921875, 0.9921875, -0.9921875], [0.9921875, 0.9921875, 0.9921875, -0.9921875], [0.0985917506032679, 0.09854235894012589, 0.09854258803171884, -0.09858215624546432]], [0.0500138897629957, 0.05001527567198765, 0.05001435043390299, -0.050014271460239144], [[-0.9921875], [-0.9921875], [-0.9921875], [0.9921875]], [-0.11692958503637083]], 'weights1': [[127, 127, 127, 13], [127, 127, 127, 13], [127, 127, 127, 13], [-127, -127, -127, -13]], 'bias1': [819, 819, 819, -819], 'weights2': [[-127, -127, -127, 127], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], 'bias2': [-1916, 0, 0, 0], 'float_test_accuracy': 0.981549815498155, 'quantized_math_test_accuracy': 0.981549815498155}

def _round_away(values):
    return np.sign(values) * np.floor(np.abs(values) + 0.5)

def preprocess(features):
    """Normalize raw features with frozen training statistics, then clip.

    Accepts a single length-4 vector or an (N, 4) array. Returns (N, 4).
    """
    x = np.asarray(features, dtype=np.float64)
    if x.ndim == 1:
        x = x.reshape(1, -1)
    if x.ndim != 2 or x.shape[1] != 4 or not np.isfinite(x).all():
        raise ValueError('Expected finite raw features with shape (4,) or (N, 4)')
    return np.clip((x - MODEL['normalization_mean']) /
                   MODEL['normalization_scale'], -1, 127 / 128)

def predict_proba(features, *, quantized=True):
    """Return one class-1 probability per row of raw input features."""
    x = preprocess(features)
    w, b, v, c = [np.asarray(a, dtype=np.float64)
                  for a in MODEL['float_parameters']]
    if quantized:
        x = _round_away(x * 128) / 128
        w = _round_away(w * 128) / 128
        v = _round_away(v * 128) / 128
        b = _round_away(b * 16384) / 16384
        c = _round_away(c * 16384) / 16384
    h = np.tanh(x @ w + b)
    if quantized:
        h = np.clip(_round_away(h * 128) / 128, -1, 127 / 128)
    return (1 / (1 + np.exp(-(h @ v + c))))[:, 0]

def predict(features, *, quantized=True):
    """Return dataset class labels; probability >= 0.5 maps to class 1."""
    return (predict_proba(features, quantized=quantized) >= 0.5).astype(np.int64)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('features', nargs=4, type=float)
    parser.add_argument('--float', dest='floating', action='store_true',
                        help='Use the original floating-point trained parameters')
    args = parser.parse_args()
    probability = float(predict_proba(args.features, quantized=not args.floating)[0])
    print(f'class={int(probability >= 0.5)} probability_class_1={probability:.12f}')
