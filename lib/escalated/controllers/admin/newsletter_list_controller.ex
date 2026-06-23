defmodule Escalated.Controllers.Admin.NewsletterListController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html, :json]
  import Ecto.Query

  alias Escalated.Controllers.NewsletterHttp, as: NH
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.Contact
  alias Escalated.Schemas.Newsletter.{NewsletterList, NewsletterListMember}
  alias Escalated.Services.Newsletter.{ContactSegmentResolver, Permission}

  def index(conn, _params) do
    conn = Permission.require_manage!(conn)

    UIRenderer.render_page(conn, "Escalated/Admin/Newsletters/Lists/Index", %{
      lists: NH.lists_with_counts(Escalated.repo())
    })
  end

  def create(conn, _params) do
    conn = Permission.require_manage!(conn)
    UIRenderer.render_page(conn, "Escalated/Admin/Newsletters/Lists/Create", %{})
  end

  def store(conn, params) do
    conn = Permission.require_manage!(conn)

    with {:ok, attrs} <- validate_store(params) do
      attrs = Map.put(attrs, :created_by, NH.user_id(conn))

      case Escalated.repo().insert(NewsletterList.changeset(%NewsletterList{}, attrs)) do
        {:ok, list} -> NH.redirect(conn, "#{NH.newsletters_base()}/lists/#{list.id}")
        {:error, cs} -> NH.bad_request(conn, errors(cs))
      end
    else
      {:error, e} -> NH.bad_request(conn, e)
    end
  end

  def show(conn, %{"list" => id}) do
    conn = Permission.require_manage!(conn)
    repo = Escalated.repo()

    with %NewsletterList{} = list <- repo.get(NewsletterList, id) do
      members =
        from(m in NewsletterListMember,
          join: c in Contact,
          on: c.id == m.contact_id,
          where: m.list_id == ^list.id,
          order_by: [desc: m.id],
          limit: 100,
          select: %{id: m.id, contact: %{id: c.id, name: c.name, email: c.email}}
        )
        |> repo.all()

      match_count =
        if list.kind == "dynamic" do
          ContactSegmentResolver.count_matches(list.filter_json || %{"rules" => []})
        else
          0
        end

      [serialized] = NH.lists_with_counts(repo) |> Enum.filter(&(&1.id == list.id))

      UIRenderer.render_page(conn, "Escalated/Admin/Newsletters/Lists/Show", %{
        list: serialized || Map.put(list, :member_count, 0),
        members: members,
        matchCount: match_count
      })
    else
      _ -> conn |> put_status(404) |> json(%{error: "List not found"})
    end
  end

  def update(conn, %{"list" => id} = params) do
    conn = Permission.require_manage!(conn)
    repo = Escalated.repo()

    with %NewsletterList{} = list <- repo.get(NewsletterList, id),
         {:ok, attrs} <- validate_update(params) do
      case repo.update(NewsletterList.changeset(list, attrs)) do
        {:ok, _} -> NH.redirect(conn, "#{NH.newsletters_base()}/lists/#{list.id}")
        {:error, cs} -> NH.bad_request(conn, errors(cs))
      end
    else
      nil -> conn |> put_status(404) |> json(%{error: "List not found"})
      {:error, e} -> NH.bad_request(conn, e)
    end
  end

  def delete(conn, %{"list" => id}) do
    conn = Permission.require_manage!(conn)
    repo = Escalated.repo()

    with %NewsletterList{} = list <- repo.get(NewsletterList, id) do
      repo.delete(list)
      NH.redirect(conn, "#{NH.newsletters_base()}/lists")
    else
      _ -> conn |> put_status(404) |> json(%{error: "List not found"})
    end
  end

  def add_member(conn, %{"list" => id} = params) do
    conn = Permission.require_manage!(conn)
    repo = Escalated.repo()

    with %NewsletterList{kind: "static"} = list <- repo.get(NewsletterList, id),
         {:ok, contact_id} <- NH.required_integer(params, "contact_id") do
      if is_nil(repo.get(Contact, contact_id)) do
        NH.bad_request(conn, %{"contact_id" => ["does not exist"]})
      else
        attrs = %{
          list_id: list.id,
          contact_id: contact_id,
          added_by: NH.user_id(conn),
          added_at: DateTime.utc_now() |> DateTime.truncate(:second)
        }

        %NewsletterListMember{}
        |> NewsletterListMember.changeset(attrs)
        |> repo.insert(on_conflict: :nothing)

        NH.redirect(conn, "#{NH.newsletters_base()}/lists/#{list.id}")
      end
    else
      %NewsletterList{} -> NH.abort422(conn, "Only static lists support members")
      nil -> conn |> put_status(404) |> json(%{error: "List not found"})
      {:error, _, msg} -> NH.bad_request(conn, %{"contact_id" => [msg]})
    end
  end

  def remove_member(conn, %{"list" => id, "contact_id" => contact_id}) do
    conn = Permission.require_manage!(conn)
    repo = Escalated.repo()

    with %NewsletterList{kind: "static"} = list <- repo.get(NewsletterList, id) do
      from(m in NewsletterListMember,
        where: m.list_id == ^list.id and m.contact_id == ^String.to_integer(contact_id)
      )
      |> repo.delete_all()

      NH.redirect(conn, "#{NH.newsletters_base()}/lists/#{list.id}")
    else
      %NewsletterList{} -> NH.abort422(conn, "Only static lists support members")
      _ -> conn |> put_status(404) |> json(%{error: "List not found"})
    end
  end

  def import_csv(conn, %{"list" => id} = params) do
    conn = Permission.require_manage!(conn)
    repo = Escalated.repo()

    with %NewsletterList{kind: "static"} = list <- repo.get(NewsletterList, id),
         %Plug.Upload{path: path} <- params["file"] || params["csv"] do
      count =
        path
        |> File.read!()
        |> String.split(~r/\r?\n/, trim: true)
        |> Enum.count(fn row ->
          [email | _] = String.split(row, ",", parts: 2)

          if NH.valid_email?(email) do
            email = Contact.normalize_email(email)

            contact =
              case repo.get_by(Contact, email: email) do
                nil ->
                  {:ok, c} = repo.insert(Contact.changeset(%Contact{}, %{email: email, name: ""}))
                  c

                c ->
                  c
              end

            repo.insert(
              NewsletterListMember.changeset(%NewsletterListMember{}, %{
                list_id: list.id,
                contact_id: contact.id,
                added_by: NH.user_id(conn),
                added_at: DateTime.utc_now() |> DateTime.truncate(:second)
              }),
              on_conflict: :nothing
            )

            true
          else
            false
          end
        end)

      conn
      |> put_flash(:info, "Imported #{count} contacts")
      |> NH.redirect("#{NH.newsletters_base()}/lists/#{list.id}")
    else
      %NewsletterList{} -> NH.abort422(conn, "Only static lists support CSV import")
      _ -> NH.bad_request(conn, %{"file" => ["is required"]})
    end
  end

  defp validate_store(params) do
    checks = [
      {:name, NH.required_string(params, "name", 255)},
      {:description, NH.optional_string(params, "description")},
      {:kind, NH.assert_one_of(param(params, "kind"), "kind", ~w(static dynamic))},
      {:filter_json, {:ok, filter_json(params)}}
    ]

    case NH.collect_errors(Enum.map(checks, fn {_, r} -> r end)) do
      errors when map_size(errors) > 0 -> {:error, errors}
      _ -> {:ok, Enum.into(checks, %{}, fn {k, {:ok, v}} -> {k, v} end)}
    end
  end

  defp validate_update(params) do
    checks = [
      {:name,
       if(param(params, "name"), do: NH.required_string(params, "name", 255), else: {:ok, nil})},
      {:description, NH.optional_string(params, "description")},
      {:filter_json, {:ok, filter_json(params)}}
    ]

    attrs =
      checks
      |> Enum.flat_map(fn
        {_, {:ok, nil}} -> []
        {k, {:ok, v}} -> [{k, v}]
        _ -> []
      end)
      |> Enum.into(%{})

    case NH.collect_errors(Enum.map(checks, fn {_, r} -> r end)) do
      errors when map_size(errors) > 0 -> {:error, errors}
      _ -> {:ok, attrs}
    end
  end

  defp filter_json(params) do
    case param(params, "filter_json") do
      nil -> nil
      v when is_map(v) -> v
      _ -> %{"rules" => []}
    end
  end

  defp param(params, key), do: Map.get(params, key) || Map.get(params, to_string(key))
  defp errors(cs), do: Ecto.Changeset.traverse_errors(cs, fn {m, _} -> m end)
end
