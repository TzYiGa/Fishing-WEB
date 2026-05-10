#!/usr/bin/env python3
"""
自 Copernicus Marine 讀取 uo/vo，篩選台灣海域，輸出 Flutter 用 JSON。

資料來源（二擇一，預設本機走 OPeNDAP）：
  1) 官方 Python 套件 copernicusmarine（建議 GitHub Actions／雲端）：以 dataset_id 遠端子集，
     避開部分網路環境對 nrt.cmems-du.eu OPeNDAP 回傳 HTML 攔截頁的問題。
  2) 直接 OPeNDAP URL（本機或設 CMEMS_OPENDAP_URL）：xarray + netCDF4。

預設 OPeNDAP（歷史相容）：
  https://nrt.cmems-du.eu/thredds/dodsC/global-analysis-forecast-phy-001-024-daily

預設 dataset_id（GLOBAL「Currents, daily」含 uo/vo）：
  cmems_mod_glo_phy-cur_anfc_0.083deg_P1D-m

環境變數：
  CMEMS_USE_COPERNICUSMARINE  設為 1 時優先使用 copernicusmarine
  CMEMS_DATASET_ID            覆寫預設 dataset_id
  CMEMS_OPENDAP_URL           僅 OPeNDAP 模式：覆寫 URL
  CMEMS_VECTOR_JSON_OUT       輸出路徑
  COPERNICUSMARINE_SERVICE_USERNAME / PASSWORD  或 CMEMS_USER / CMEMS_PASSWORD
  CMEMS_FALLBACK_OPENDAP      設為 1 且 CMEMS_USE_COPERNICUSMARINE=1 時，marine 失敗後仍嘗試 OPeNDAP
"""

from __future__ import annotations

import datetime as dt
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
DEFAULT_DATASET_ID = "cmems_mod_glo_phy-cur_anfc_0.083deg_P1D-m"
OUT_DEFAULT = Path("assets/data/copernicus_ocean_vectors.json")

LON_MIN, LON_MAX = 118.0, 125.0
LAT_MIN, LAT_MAX = 20.0, 27.0


def _lon_lat_names(ds: xr.Dataset) -> tuple[str, str]:
    for lon_c, lat_c in (
        ("longitude", "latitude"),
        ("lon", "lat"),
        ("x", "y"),
    ):
        if lon_c in ds.dims and lat_c in ds.dims:
            return lon_c, lat_c
    raise RuntimeError(f"無法辨識經緯度維度，目前 dims: {dict(ds.dims)}")


def _open_via_copernicusmarine() -> xr.Dataset:
    import copernicusmarine as cm

    dataset_id = os.environ.get("CMEMS_DATASET_ID", DEFAULT_DATASET_ID).strip()
    user = (
        os.environ.get("COPERNICUSMARINE_SERVICE_USERNAME")
        or os.environ.get("CMEMS_USER")
        or ""
    ).strip()
    pwd = (
        os.environ.get("COPERNICUSMARINE_SERVICE_PASSWORD")
        or os.environ.get("CMEMS_PASSWORD")
        or ""
    ).strip()

    end = dt.datetime.now(dt.timezone.utc)
    start = end - dt.timedelta(days=7)

    kwargs: dict = {
        "dataset_id": dataset_id,
        "variables": ["uo", "vo"],
        "minimum_longitude": LON_MIN,
        "maximum_longitude": LON_MAX,
        "minimum_latitude": LAT_MIN,
        "maximum_latitude": LAT_MAX,
        "start_datetime": start,
        "end_datetime": end,
    }
    if user and pwd:
        kwargs["username"] = user
        kwargs["password"] = pwd

    print(
        f"使用 copernicusmarine.open_dataset({dataset_id!r})，時段 {start.date()}–{end.date()}",
        file=sys.stderr,
    )
    return cm.open_dataset(**kwargs)


def _open_via_opendap() -> xr.Dataset:
    url = os.environ.get("CMEMS_OPENDAP_URL", DEFAULT_URL).strip()
    print(f"開啟 OPeNDAP: {url}", file=sys.stderr)
    try:
        import netCDF4  # noqa: F401

        return xr.open_dataset(url, decode_times=True, engine="netcdf4")
    except ImportError as e:
        raise RuntimeError(
            "OPeNDAP 需要 netCDF4，請執行: pip install -r tool/requirements-copernicus.txt"
        ) from e


def _load_dataset() -> xr.Dataset:
    use_marine = os.environ.get("CMEMS_USE_COPERNICUSMARINE", "").strip() == "1"
    allow_opendap_fallback = (
        os.environ.get("CMEMS_FALLBACK_OPENDAP", "").strip() == "1"
    )
    if use_marine:
        try:
            return _open_via_copernicusmarine()
        except ImportError:
            print(
                "已設 CMEMS_USE_COPERNICUSMARINE=1 但未安裝 copernicusmarine",
                file=sys.stderr,
            )
            if not allow_opendap_fallback:
                sys.exit(1)
            print("已設 CMEMS_FALLBACK_OPENDAP=1，改試 OPeNDAP", file=sys.stderr)
            return _open_via_opendap()
        except Exception as e:
            if allow_opendap_fallback:
                print(f"copernicusmarine 失敗 ({e})，改試 OPeNDAP", file=sys.stderr)
                return _open_via_opendap()
            print(
                f"copernicusmarine 失敗: {e}\n"
                "請檢查 CMEMS_DATASET_ID、帳密或網路。若仍要嘗試 OPeNDAP，請設 CMEMS_FALLBACK_OPENDAP=1。",
                file=sys.stderr,
            )
            sys.exit(1)
    return _open_via_opendap()


def main() -> None:
    out_path = Path(os.environ.get("CMEMS_VECTOR_JSON_OUT", OUT_DEFAULT))
    out_path.parent.mkdir(parents=True, exist_ok=True)

    ds = _load_dataset()
    try:
        lon_n, lat_n = _lon_lat_names(ds)

        sub = ds.sel({lon_n: slice(LON_MIN, LON_MAX), lat_n: slice(LAT_MIN, LAT_MAX)})
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
    finally:
        ds.close()


if __name__ == "__main__":
    main()
