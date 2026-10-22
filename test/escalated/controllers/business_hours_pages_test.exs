defmodule Escalated.Controllers.BusinessHoursPagesTest do
  @moduledoc """
  `Escalated/Admin/BusinessHours/Index` and `Form` against the props the
  shared Vue pages read and the routes they post to (escalated-laravel's
  `Admin\\BusinessHoursController`).
  """
  use Escalated.PageCase

  alias Escalated.Schemas.{BusinessSchedule, Department, Holiday, SlaPolicy}

  defp repo, do: Escalated.repo()

  @week %{
    "monday" => %{"start" => "09:00", "end" => "17:00"},
    "tuesday" => %{"start" => "09:00", "end" => "17:00"},
    "wednesday" => %{"start" => "09:00", "end" => "17:00"},
    "thursday" => %{"start" => "09:00", "end" => "17:00"},
    "friday" => %{"start" => "09:00", "end" => "17:00"},
    "saturday" => %{"start" => "", "end" => ""},
    "sunday" => %{"start" => "", "end" => ""}
  }

  @schedule_keys ~w(id name timezone is_default schedule holidays created_at updated_at)
  @holiday_keys ~w(id schedule_id name date recurring)

  setup do
    %{admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true})}
  end

  defp schedule!(attrs \\ %{}) do
    schedule =
      %BusinessSchedule{}
      |> BusinessSchedule.changeset(
        Map.merge(%{name: "Office", timezone: "Europe/London", hours: @week}, attrs)
      )
      |> repo().insert!()

    repo().insert!(
      Holiday.changeset(%Holiday{}, %{
        name: "Christmas",
        date: ~D[2026-12-25],
        is_recurring: true,
        business_schedule_id: schedule.id
      })
    )

    schedule
  end

  defp body(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Support desk",
        "timezone" => "America/New_York",
        "is_default" => true,
        "schedule" => @week,
        "holidays" => [
          %{"name" => "New Year", "date" => "2027-01-01", "recurring" => true},
          %{"name" => "Offsite", "date" => "2026-11-20", "recurring" => false}
        ]
      },
      overrides
    )
  end

  test "Index lists schedules with their holidays", %{admin: admin} do
    schedule = schedule!(%{is_default: true})

    props =
      visit(:get, "/support/admin/business-hours", admin)
      |> page!("Escalated/Admin/BusinessHours/Index")

    assert [row] = props["schedules"]
    assert_keys(row, @schedule_keys, "schedule")
    assert row["id"] == schedule.id
    assert row["timezone"] == "Europe/London"
    assert row["is_default"] == true
    assert row["schedule"]["monday"] == %{"start" => "09:00", "end" => "17:00"}
    assert row["schedule"]["sunday"] == %{"start" => "", "end" => ""}

    assert [holiday] = row["holidays"]
    assert_keys(holiday, @holiday_keys, "holiday")
    assert holiday["schedule_id"] == schedule.id
    assert holiday["date"] == "2026-12-25"
    assert holiday["recurring"] == true
  end

  test "rows written with the old enabled flags read as open and closed days", %{admin: admin} do
    schedule!(%{hours: BusinessSchedule.default_hours()})

    [row] =
      visit(:get, "/support/admin/business-hours", admin)
      |> page!("Escalated/Admin/BusinessHours/Index")
      |> Map.fetch!("schedules")

    assert row["schedule"]["monday"] == %{"start" => "09:00", "end" => "17:00"}
    assert row["schedule"]["saturday"] == %{"start" => "", "end" => ""}
  end

  test "create renders the form with the time zones", %{admin: admin} do
    props =
      visit(:get, "/support/admin/business-hours/create", admin)
      |> page!("Escalated/Admin/BusinessHours/Form")

    assert_keys(props, ~w(timezones))
    assert "UTC" in props["timezones"]
    assert "America/New_York" in props["timezones"]
    refute Map.has_key?(props, "schedule")
  end

  test "edit renders the form with the schedule", %{admin: admin} do
    schedule = schedule!()

    props =
      visit(:get, "/support/admin/business-hours/#{schedule.id}/edit", admin)
      |> page!("Escalated/Admin/BusinessHours/Form")

    assert_keys(props, ~w(timezones schedule))
    assert_keys(props["schedule"], @schedule_keys, "schedule")
    assert [holiday] = props["schedule"]["holidays"]
    assert_keys(holiday, @holiday_keys, "holiday")
  end

  test "edit of an unknown schedule is a 404", %{admin: admin} do
    assert visit(:get, "/support/admin/business-hours/999999/edit", admin).status == 404
  end

  test "store creates the schedule and its holidays, taking over the default", %{admin: admin} do
    old_default = schedule!(%{is_default: true})

    conn = visit(:post, "/support/admin/business-hours", admin, body())
    assert conn.status in [302, 303]
    assert location(conn) == "/support/admin/business-hours"

    created = repo().get_by!(BusinessSchedule, name: "Support desk") |> repo().preload(:holidays)
    assert created.timezone == "America/New_York"
    assert created.is_default
    assert created.hours["monday"] == %{"start" => "09:00", "end" => "17:00"}

    assert Enum.map(created.holidays, &{&1.name, &1.date, &1.is_recurring}) |> Enum.sort() ==
             [{"New Year", ~D[2027-01-01], true}, {"Offsite", ~D[2026-11-20], false}]

    refute repo().get!(BusinessSchedule, old_default.id).is_default
  end

  test "update replaces the fields and the holidays", %{admin: admin} do
    schedule = schedule!()

    conn =
      visit(
        :put,
        "/support/admin/business-hours/#{schedule.id}",
        admin,
        body(%{
          "name" => "Renamed",
          "is_default" => false,
          "holidays" => [%{"name" => "Boxing Day", "date" => "2026-12-26", "recurring" => false}]
        })
      )

    assert conn.status in [302, 303]
    assert location(conn) == "/support/admin/business-hours"

    updated = repo().get!(BusinessSchedule, schedule.id) |> repo().preload(:holidays)
    assert updated.name == "Renamed"
    assert updated.timezone == "America/New_York"
    assert Enum.map(updated.holidays, & &1.name) == ["Boxing Day"]
  end

  test "destroy removes the schedule and clears references to it", %{admin: admin} do
    schedule = schedule!()

    policy =
      repo().insert!(
        SlaPolicy.changeset(%SlaPolicy{}, %{
          name: "Gold",
          first_response_hours: %{"medium" => 1},
          resolution_hours: %{"medium" => 4},
          business_schedule_id: schedule.id
        })
      )

    dept =
      repo().insert!(
        Department.changeset(%Department{}, %{name: "Billing", business_schedule_id: schedule.id})
      )

    conn = visit(:delete, "/support/admin/business-hours/#{schedule.id}", admin)
    assert conn.status in [302, 303]
    assert location(conn) == "/support/admin/business-hours"

    assert repo().get(BusinessSchedule, schedule.id) == nil
    assert repo().aggregate(Holiday, :count) == 0
    assert repo().get!(SlaPolicy, policy.id).business_schedule_id == nil
    assert repo().get!(Department, dept.id).business_schedule_id == nil
  end

  test "invalid input goes back without saving", %{admin: admin} do
    for bad <- [
          body(%{"name" => ""}),
          body(%{"timezone" => "Mars/Olympus_Mons"}),
          body(%{"schedule" => "nine to five"}),
          body(%{"holidays" => [%{"name" => "", "date" => "2026-12-25"}]}),
          body(%{"holidays" => [%{"name" => "Bad", "date" => "not a date"}]})
        ] do
      conn = visit(:post, "/support/admin/business-hours", admin, bad)
      assert conn.status in [302, 303]
      assert location(conn) != "/support/admin/business-hours"
    end

    assert repo().aggregate(BusinessSchedule, :count) == 0
  end

  test "an SLA policy keeps its schedule when the form does not send one", %{admin: admin} do
    schedule = schedule!()

    policy =
      repo().insert!(
        SlaPolicy.changeset(%SlaPolicy{}, %{
          name: "Gold",
          first_response_hours: %{"medium" => 1},
          resolution_hours: %{"medium" => 4},
          business_schedule_id: schedule.id
        })
      )

    visit(:put, "/support/admin/sla-policies/#{policy.id}", admin, %{"name" => "Platinum"})
    assert repo().get!(SlaPolicy, policy.id).business_schedule_id == schedule.id

    visit(:put, "/support/admin/sla-policies/#{policy.id}", admin, %{
      "business_schedule_id" => nil
    })

    assert repo().get!(SlaPolicy, policy.id).business_schedule_id == nil
  end

  test "non-admins are turned away" do
    agent = host_user!(%{name: "Agent", is_admin: false, is_agent: true})
    conn = visit(:get, "/support/admin/business-hours", agent)
    assert conn.status in [302, 303, 401, 403]
  end
end
