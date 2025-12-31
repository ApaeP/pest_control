# frozen_string_literal: true

require "rails_helper"

RSpec.describe PestControl::DashboardHelper, type: :helper do
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
  end
end
