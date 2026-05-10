#!/usr/bin/env python3
"""
自 Copernicus Marine Service OPeNDAP 讀取 uo/vo，篩選台灣海域，輸出 Flutter 用 JSON。

資料集（預設）：
  global-analysis-forecast-phy-001-024-daily
  https://nrt.cmems-du.eu/thredds/dodsC/global-analysis-forecast-phy-001-024-daily

輸出格式（陣列）：
  [ { "lat": 25.0, "lng": 121.5, "u": 0.8, "v": -0.3 }, ... ]

用法：
  pip install -r tool/requirements-copernicus.txt
  python tool/export_copernicus_ocean_vectors.py

自動化（免手動）：
  倉庫已含 GitHub Actions：`.github/workflows/update-copernicus-ocean-vectors.yml`
  每日排程匯出並 push `assets/data/copernicus_ocean_vectors.json`。
  若需登入 CMEMS，於 GitHub Repository → Settings → Secrets 新增 CMEMS_USER、CMEMS_PASSWORD。

  若希望「不重 build 網頁」也能更新海流，可把該 JSON 放到公開 HTTPS，
  並在 dart-define 設定 OCEAN_VECTORS_JSON_URL 指向該 URL（見 dart_defines.example.json）。

環境變數（若 THREDDS 需認證，請依 CMEMS 帳號設定）：
  CMEMS_OPENDAP_URL  覆寫 OPeNDAP 基底 URL
  CMEMS_USER / CMEMS_PASSWORD  部分伺服器會讀取 .netrc，請自行設定
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

try:
    import numpy as np
    import xarray as xr
except ImportError:
    print("請先執行: pip install -r tool/requirements-copernicus.txt", file=sys.stderr)
    sys.exit(1)

DEFAULT_URL = (
    "https://nrt.cmems-du.eu/thredds/dodsC/global-analysis-forecast-phy-001-024-daily"
)
OUT_DEFAULT = Path("assets/data/copernicus_ocean_vectors.json")


def _lon_lat_names(ds: xr.Dataset) -> tuple[str, str]:
    for lon_c, lat_c in (
        ("longitude", "latitude"),
        ("lon", "lat"),
        ("x", "y"),
    ):
        if lon_c in ds.dims and lat_c in ds.dims:
            return lon_c, lat_c
    raise RuntimeError(f"無法辨識經緯度維度，目前 dims: {dict(ds.dims)}")


def main() -> None:
    url = os.environ.get("CMEMS_OPENDAP_URL", DEFAULT_URL)
    out_path = Path(os.environ.get("CMEMS_VECTOR_JSON_OUT", OUT_DEFAULT))
    out_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"開啟 OPeNDAP: {url}", file=sys.stderr)
    ds = xr.open_dataset(url, decode_times=True)
    lon_n, lat_n = _lon_lat_names(ds)

    # 台灣海域；若 latitude 遞減，slice 終點需大於起點在數值上仍代表「南緣到北緣」由 xarray 處理
    sub = ds.sel({lon_n: slice(118.0, 125.0), lat_n: slice(20.0, 27.0)})
    if "time" in sub.dims:
        sub = sub.isel(time=-1)

    if "uo" not in sub or "vo" not in sub:
        raise RuntimeError(f"資料集缺少 uo/vo，variables: {list(sub.data_vars)}")

    def surface_first(da: xr.DataArray) -> xr.DataArray:
        for dim in ("depth", "elevation", "deptho", "lev"):
            if dim in da.dims:
                return da.isel({dim: 0})
        return da.squeeze(drop=True)

    uo = surface_first(sub["uo"])
    vo = surface_first(sub["vo"])
    stacked = xr.Dataset({"u": uo, "v": vo}).to_dataframe().reset_index()
    stacked = stacked.rename(columns={lat_n: "lat", lon_n: "lng"})

    records: list[dict[str, float]] = []
    for _, row in stacked.iterrows():
        u = float(row["u"]) if row["u"] == row["u"] else None
        v = float(row["v"]) if row["v"] == row["v"] else None
        if u is None or v is None:
            continue
        if np.isnan(u) or np.isnan(v):
            continue
        records.append(
            {
                "lat": float(row["lat"]),
                "lng": float(row["lng"]),
                "u": u,
                "v": v,
            }
        )

    out_path.write_text(json.dumps(records, ensure_ascii=False), encoding="utf-8")
    print(f"已寫入 {len(records)} 筆 → {out_path.resolve()}", file=sys.stderr)


if __name__ == "__main__":
    main()
