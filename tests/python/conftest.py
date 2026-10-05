import os


def pytest_collection_modifyitems(config, items):
    suite = os.environ.get("NVIM_TEST_SUITE", "fast")
    match = os.environ.get("NVIM_TEST_MATCH", "")
    keep, deselected = [], []
    for item in items:
        params = getattr(getattr(item, "callspec", None), "params", {})
        case = params.get("case")
        # An empty legacy parametrization uses pytest's NOTSET sentinel when
        # FILE selects only native tests.
        source = case.get("file", "") if isinstance(case, dict) else ""
        matching = not match or match in item.nodeid or match in source
        (
            keep
            if matching and (suite == "all" or item.get_closest_marker(suite))
            else deselected
        ).append(item)
    items[:] = keep
    config.hook.pytest_deselected(items=deselected)
