defmodule Employin.TimeZonesTest do
  use ExUnit.Case, async: true

  alias Employin.TimeZones

  test "normalize/1 falls back to UTC for unknown zones" do
    assert TimeZones.normalize("Europe/Berlin") == "Europe/Berlin"
    assert TimeZones.normalize("Mars/Olympus_Mons") == "Etc/UTC"
    assert TimeZones.normalize(nil) == "Etc/UTC"
  end

  test "local_date/2 uses the zone's calendar day" do
    assert TimeZones.local_date(~U[2026-03-01 20:00:00Z], "Asia/Dhaka") == ~D[2026-03-02]
    assert TimeZones.local_date(~U[2026-03-01 03:00:00Z], "America/New_York") == ~D[2026-02-28]
  end

  describe "local_to_utc/3 around DST transitions (America/New_York, 2026)" do
    test "times that don't exist move past the gap" do
      # Clocks jump from 02:00 to 03:00 on March 8.
      assert TimeZones.local_to_utc(~D[2026-03-08], ~T[02:30:00], "America/New_York") ==
               ~U[2026-03-08 07:00:00Z]
    end

    test "times that happen twice use the first occurrence" do
      # Clocks fall back from 02:00 to 01:00 on November 1.
      assert TimeZones.local_to_utc(~D[2026-11-01], ~T[01:30:00], "America/New_York") ==
               ~U[2026-11-01 05:30:00Z]
    end
  end
end
