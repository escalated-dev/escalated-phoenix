defmodule Escalated.Controllers.ScheduleOptionsTest do
  @moduledoc """
  The shared `Admin/SlaPolicies/Form` and `Admin/Departments/Form` show a
  Business hours schedule picker when given `schedules` (`[{id, name}]`, by
  name) and post `business_schedule_id`, as escalated-laravel's
  `SlaPolicyController` and `DepartmentController` serve them.
  """
  use Escalated.PageCase

  alias Escalated.Schemas.{BusinessSchedule, Department, SlaPolicy}

  defp repo, do: Escalated.repo()

  @hours %{"low" => 24, "medium" => 8, "high" => 4}

  setup do
    zulu = schedule!("Zulu shift")
    alpha = schedule!("Alpha weekend")

    %{
      admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true}),
      zulu: zulu,
      alpha: alpha,
      expected: [
        %{"id" => alpha.id, "name" => "Alpha weekend"},
        %{"id" => zulu.id, "name" => "Zulu shift"}
      ]
    }
  end

  defp schedule!(name) do
    %BusinessSchedule{}
    |> BusinessSchedule.changeset(%{name: name, timezone: "UTC"})
    |> repo().insert!()
  end

  defp department!(attrs) do
    %Department{}
    |> Department.changeset(Map.merge(%{name: "Billing"}, attrs))
    |> repo().insert!()
  end

  test "the SLA policy form lists the schedules by name", %{admin: admin, expected: expected} do
    props =
      visit(:get, "/support/admin/sla-policies/create", admin)
      |> page!("Escalated/Admin/SlaPolicies/Form")

    assert props["schedules"] == expected

    policy =
      repo().insert!(
        SlaPolicy.changeset(%SlaPolicy{}, %{
          name: "Gold",
          first_response_hours: @hours,
          resolution_hours: @hours
        })
      )

    props =
      visit(:get, "/support/admin/sla-policies/#{policy.id}/edit", admin)
      |> page!("Escalated/Admin/SlaPolicies/Form")

    assert props["schedules"] == expected
  end

  test "an SLA policy refuses a schedule that does not exist", %{admin: admin} do
    conn =
      visit(:post, "/support/admin/sla-policies", admin, %{
        "name" => "Ghost",
        "first_response_hours" => @hours,
        "resolution_hours" => @hours,
        "business_schedule_id" => 999_999
      })

    assert conn.status in [302, 303]
    assert location(conn) != "/support/admin/sla-policies"
    refute repo().get_by(SlaPolicy, name: "Ghost")
  end

  test "the department form lists the schedules and the saved one",
       %{admin: admin, zulu: zulu, expected: expected} do
    props =
      visit(:get, "/support/admin/departments/new", admin)
      |> page!("Escalated/Admin/Departments/Form")

    assert props["schedules"] == expected

    dept = department!(%{business_schedule_id: zulu.id})

    for path <- [
          "/support/admin/departments/#{dept.id}/edit",
          "/support/admin/departments/#{dept.id}"
        ] do
      props = visit(:get, path, admin) |> page!("Escalated/Admin/Departments/Form")
      assert props["schedules"] == expected
      assert props["department"]["business_schedule_id"] == zulu.id
    end
  end

  test "the department form saves the schedule only when it sends one",
       %{admin: admin, zulu: zulu} do
    conn =
      visit(:post, "/support/admin/departments", admin, %{
        "name" => "Returns",
        "business_schedule_id" => zulu.id
      })

    assert conn.status in [302, 303]
    dept = repo().get_by!(Department, name: "Returns")
    assert dept.business_schedule_id == zulu.id

    visit(:put, "/support/admin/departments/#{dept.id}", admin, %{"name" => "Returns desk"})
    assert %{name: "Returns desk", business_schedule_id: id} = repo().get!(Department, dept.id)
    assert id == zulu.id

    visit(:put, "/support/admin/departments/#{dept.id}", admin, %{"business_schedule_id" => nil})
    assert repo().get!(Department, dept.id).business_schedule_id == nil

    conn =
      visit(:put, "/support/admin/departments/#{dept.id}", admin, %{
        "business_schedule_id" => 999_999
      })

    assert conn.status in [302, 303]
    assert repo().get!(Department, dept.id).business_schedule_id == nil

    conn =
      visit(:post, "/support/admin/departments", admin, %{
        "name" => "Ghost",
        "business_schedule_id" => 999_999
      })

    assert conn.status in [302, 303]
    refute repo().get_by(Department, name: "Ghost")
  end

  test "the nested department body still works", %{admin: admin, zulu: zulu} do
    visit(:post, "/support/admin/departments", admin, %{
      "department" => %{"name" => "Nested", "business_schedule_id" => zulu.id}
    })

    assert repo().get_by!(Department, name: "Nested").business_schedule_id == zulu.id
  end
end
