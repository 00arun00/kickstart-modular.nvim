import os


def pytest_collection_modifyitems(config, items):
    suite = os.environ.get("NVIM_TEST_SUITE", "fast")
    match = os.environ.get("NVIM_TEST_MATCH", "")
    keep, deselected = [], []
    for item in items:
        params = getattr(getattr(item, "callspec", None), "params", {})
        source = params.get("case", {}).get("file", "")
        matching = not match or match in item.nodeid or match in source
        (
            keep
            if matching and (suite == "all" or item.get_closest_marker(suite))
            else deselected
        ).append(item)
    items[:] = keep
    config.hook.pytest_deselected(items=deselected)
