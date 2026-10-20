defmodule Escalated.OutboundUrlGuardTest do
  use ExUnit.Case, async: true

  alias Escalated.OutboundUrlGuard, as: Guard

  defp resolver(addresses), do: [resolver: fn _host -> addresses end]

  describe "public_address_for/2" do
    test "allows http and https URLs whose host resolves only to public addresses" do
      assert {:ok, {93, 184, 215, 14}} =
               Guard.public_address_for("https://hooks.example/in", resolver(["93.184.215.14"]))

      assert {:ok, {8, 8, 8, 8}} = Guard.public_address_for("http://8.8.8.8/hook")

      assert {:ok, {0x2606, 0x4700, 0, 0, 0, 0, 0, 0x1111}} =
               Guard.public_address_for("http://[2606:4700::1111]/hook")
    end

    test "refuses other schemes and malformed URLs" do
      for url <- [
            "ftp://8.8.8.8/",
            "file:///etc/passwd",
            "gopher://8.8.8.8/",
            "javascript:alert(1)",
            "http://",
            "not a url",
            "",
            nil
          ] do
        assert Guard.public_address_for(url, resolver(["8.8.8.8"])) == :error, inspect(url)
      end
    end

    test "refuses a host that does not resolve" do
      assert Guard.public_address_for("https://nowhere.example/", resolver([])) == :error
      assert Guard.public_address_for("https://nowhere.example/", resolver(["nowhere"])) == :error
    end

    test "refuses a host when any of its addresses is not public" do
      assert Guard.public_address_for(
               "https://split.example/",
               resolver(["93.184.215.14", "10.0.0.1"])
             ) == :error
    end

    test "refuses loopback, private, link-local, metadata and other reserved addresses" do
      for ip <- ~w(
            0.0.0.0 10.1.2.3 100.64.0.1 127.0.0.1 127.255.255.254 169.254.169.254
            172.16.0.1 172.31.255.255 192.0.0.8 192.0.2.1 192.168.1.1 198.18.0.1
            198.51.100.7 203.0.113.9 224.0.0.1 240.0.0.1 255.255.255.255
            :: ::1 ::ffff:127.0.0.1 ::ffff:169.254.169.254 64:ff9b::a00:1
            fc00::1 fd12:3456::1 fe80::1 fec0::1 ff02::1 2001:db8::1 2002:a00:1::1
          ) do
        refute Guard.public?(ip), ip

        assert Guard.public_address_for("http://metadata.example/", resolver([ip])) == :error,
               ip
      end
    end

    test "accepts addresses just outside the reserved ranges" do
      for ip <- ~w(9.255.255.255 11.0.0.1 100.63.255.255 100.128.0.1 172.15.255.255
                   172.32.0.1 192.167.255.255 192.169.0.1 ::ffff:8.8.8.8 2606:4700::1111) do
        assert Guard.public?(ip), ip
      end
    end

    test "uses the configured resolver when none is passed" do
      assert {:ok, {93, 184, 215, 14}} = Guard.public_address_for("https://hooks.test/in")
      refute Guard.allows?("https://not-a-test-host.example/in")
    end
  end
end
