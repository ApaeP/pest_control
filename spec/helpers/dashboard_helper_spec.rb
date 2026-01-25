# frozen_string_literal: true

require "rails_helper"

RSpec.describe PestControl::DashboardHelper, type: :helper do
  describe "#stat_card" do
    it "renders a stat card with link" do
      result = helper.stat_card(label: "Total", value: "100", color: "green", path: "/test")
      expect(result).to include("stat-card")
      expect(result).to include("Total")
      expect(result).to include("100")
    end

    it "renders with anchor" do
      result = helper.stat_card(label: "Test", value: "50", color: "blue", anchor: "section")
      expect(result).to include('href="#section"')
    end

    it "renders with trend indicator when trend provided" do
      result = helper.stat_card(
        label: "Today",
        value: "10",
        color: "blue",
        path: "/test",
        trend: { current: 10, previous: 5 }
      )
      expect(result).to include("stat-value-wrapper")
      expect(result).to include("trend")
      expect(result).to include("↑")
    end

    it "renders without trend indicator when trend is nil" do
      result = helper.stat_card(label: "Total", value: "100", color: "green", path: "/test", trend: nil)
      expect(result).not_to include("trend-up")
      expect(result).not_to include("trend-down")
    end
  end

  describe "#trend_indicator" do
    it "shows up arrow for positive change" do
      result = helper.trend_indicator(10, 5)
      expect(result).to include("↑")
      expect(result).to include("trend-up")
      expect(result).to include("100.0%")
    end

    it "shows down arrow for negative change" do
      result = helper.trend_indicator(5, 10)
      expect(result).to include("↓")
      expect(result).to include("trend-down")
      expect(result).to include("50.0%")
    end

    it "shows neutral arrow for no change" do
      result = helper.trend_indicator(10, 10)
      expect(result).to include("→")
      expect(result).to include("trend-neutral")
      expect(result).to include("0.0%")
    end

    it "returns empty span when previous is zero" do
      result = helper.trend_indicator(10, 0)
      expect(result).to include('class="trend"')
      expect(result).not_to include("↑")
      expect(result).not_to include("↓")
    end

    it "returns empty span when previous is nil" do
      result = helper.trend_indicator(10, nil)
      expect(result).to include('class="trend"')
    end

    it "includes title with previous value" do
      result = helper.trend_indicator(10, 5)
      expect(result).to include('title="vs previous period: 5"')
    end
  end

  describe "#relative_time" do
    it "returns dash for nil time" do
      expect(helper.relative_time(nil)).to eq("—")
    end

    it "shows seconds ago for recent times" do
      result = helper.relative_time(30.seconds.ago)
      expect(result).to include("s ago")
      expect(result).to include("relative-time")
    end

    it "shows minutes ago for times within an hour" do
      result = helper.relative_time(5.minutes.ago)
      expect(result).to include("m ago")
    end

    it "shows hours ago for times within a day" do
      result = helper.relative_time(3.hours.ago)
      expect(result).to include("h ago")
    end

    it "shows days ago for times within a week" do
      result = helper.relative_time(2.days.ago)
      expect(result).to include("d ago")
    end

    it "shows date for older times" do
      result = helper.relative_time(10.days.ago)
      expect(result).to include(10.days.ago.strftime("%b"))
    end

    it "includes full timestamp in title" do
      time = 1.hour.ago
      result = helper.relative_time(time)
      expect(result).to include(time.strftime("%Y-%m-%d"))
    end
  end

  describe "#trap_type_badge" do
    let(:record) { instance_double(PestControl::TrapRecord, trap_type: "fake_login_view") }

    it "renders badge for record" do
      result = helper.trap_type_badge(record)
      expect(result).to include("badge")
      expect(result).to include("badge-green")
    end

    it "renders badge for string type" do
      result = helper.trap_type_badge("credential_capture")
      expect(result).to include("badge-red")
    end

    it "renders linkable badge" do
      allow(helper).to receive(:pest_control).and_return(
        double(pest_control_records_path: "/pest-control/records?type=fake_login_view")
      )
      result = helper.trap_type_badge(record, linkable: true)
      expect(result).to include("href=")
    end
  end

  describe "#trap_type_to_badge_class" do
    it "returns correct badge class for credential capture" do
      expect(helper.trap_type_to_badge_class("credential_capture")).to eq("badge-red")
      expect(helper.trap_type_to_badge_class("credential_capture_blocked")).to eq("badge-red")
    end

    it "returns correct badge class for fake login" do
      expect(helper.trap_type_to_badge_class("fake_login_view")).to eq("badge-green")
    end

    it "returns correct badge class for xmlrpc attack" do
      expect(helper.trap_type_to_badge_class("xmlrpc_attack")).to eq("badge-yellow")
    end

    it "returns correct badge class for fake admin" do
      expect(helper.trap_type_to_badge_class("fake_admin_access")).to eq("badge-blue")
    end

    it "returns purple for unknown types" do
      expect(helper.trap_type_to_badge_class("unknown")).to eq("badge-purple")
    end
  end

  describe "#banned_badge" do
    it "returns nil for non-banned IP" do
      expect(helper.banned_badge("1.2.3.4")).to be_nil
    end

    it "returns badge for banned IP" do
      PestControl.ban_ip!("1.2.3.4", "test")
      result = helper.banned_badge("1.2.3.4")
      expect(result).to include("🔒")
      expect(result).to include("badge-red")
    end
  end

  describe "#credentials_badge" do
    it "returns key emoji when credentials present" do
      record = instance_double(PestControl::TrapRecord, credentials: { username: "test" })
      result = helper.credentials_badge(record)
      expect(result).to include("🔑")
    end

    it "returns dash when no credentials" do
      record = instance_double(PestControl::TrapRecord, credentials: nil)
      result = helper.credentials_badge(record)
      expect(result).to include("—")
    end
  end

  describe "#ip_cell" do
    before do
      allow(helper).to receive(:pest_control).and_return(
        double(pest_control_records_path: "/pest-control/records?ip=1.2.3.4")
      )
    end

    it "renders IP with link" do
      result = helper.ip_cell("1.2.3.4")
      expect(result).to include("1.2.3.4")
      expect(result).to include("ip-cell")
    end

    it "renders IP without link" do
      result = helper.ip_cell("1.2.3.4", linkable: false)
      expect(result).to include("1.2.3.4")
    end

    it "includes banned badge for banned IPs" do
      PestControl.ban_ip!("1.2.3.4", "test")
      result = helper.ip_cell("1.2.3.4")
      expect(result).to include("🔒")
    end
  end

  describe "#pagination" do
    before do
      mock_request = Struct.new(:query_parameters).new({ page: 1 })
      mock_engine = Object.new
      mock_engine.define_singleton_method(:pest_control_records_path) { |_params = {}| "/pest-control/records" }
      allow(helper).to receive_messages(request: mock_request, pest_control: mock_engine)
    end

    it "returns nil for single page" do
      result = helper.pagination(page: 1, total_pages: 1, total_count: 10, per_page: 25)
      expect(result).to be_nil
    end

    it "renders pagination for multiple pages" do
      result = helper.pagination(page: 2, total_pages: 5, total_count: 100, per_page: 25)
      expect(result).to include("pagination")
      expect(result).to include("Page 2 of 5")
    end
  end

  describe "#filter_tag" do
    before do
      mock_request = Struct.new(:query_parameters).new({ type: "test", page: 1 })
      mock_engine = Object.new
      mock_engine.define_singleton_method(:pest_control_records_path) { |_params = {}| "/pest-control/records" }
      allow(helper).to receive_messages(request: mock_request, pest_control: mock_engine)
    end

    it "renders filter tag with remove link" do
      result = helper.filter_tag("Type", "test", :type)
      expect(result).to include("filter-tag")
      expect(result).to include("Type: test")
      expect(result).to include("×")
    end
  end

  describe "#filters_active?" do
    it "returns false when no filters" do
      allow(helper).to receive(:params).and_return({})
      expect(helper.filters_active?).to be false
    end

    it "returns true when filter param present" do
      allow(helper).to receive(:params).and_return({ filter: "today" })
      expect(helper.filters_active?).to be true
    end

    it "returns true when search param present" do
      allow(helper).to receive(:params).and_return({ q: "test" })
      expect(helper.filters_active?).to be true
    end

    it "returns true when type param present" do
      allow(helper).to receive(:params).and_return({ type: "fake_login_view" })
      expect(helper.filters_active?).to be true
    end

    it "returns true when ip param present" do
      allow(helper).to receive(:params).and_return({ ip: "1.2.3.4" })
      expect(helper.filters_active?).to be true
    end

    it "returns true when date range params present" do
      allow(helper).to receive(:params).and_return({ from: "2024-01-01", to: "2024-12-31" })
      expect(helper.filters_active?).to be true
    end
  end

  describe "#ban_toggle_button" do
    before do
      allow(helper).to receive(:pest_control).and_return(
        double(
          pest_control_ban_path: "/pest-control/ban",
          pest_control_unban_path: "/pest-control/unban"
        )
      )
    end

    it "renders Ban button for non-banned IP" do
      result = helper.ban_toggle_button("1.2.3.4")
      expect(result).to include("Ban")
      expect(result).to include("btn-danger")
    end

    it "renders Unban button for banned IP" do
      PestControl.ban_ip!("1.2.3.4", "test")
      result = helper.ban_toggle_button("1.2.3.4")
      expect(result).to include("Unban")
      expect(result).to include("btn-success")
    end

    it "renders small button when size is small" do
      result = helper.ban_toggle_button("1.2.3.4", size: :small)
      expect(result).to include("btn-sm")
    end
  end
end
