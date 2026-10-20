import importlib.util, os, sys
import pytest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.dirname(__file__))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    return m


@pytest.fixture(scope="session")
def bgs():
    return load("bgs", os.environ.get("BGS_PATH", os.path.join(REPO, "bulk_group_stamp.py")))
