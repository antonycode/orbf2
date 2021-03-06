require "rails_helper"

RSpec.describe Setup::MainEntityGroupsController, type: :controller do
  describe "When non authenticated #create" do
    it "should redirect to sign on" do
      post :create, params: { project_id: 1 }
      expect(response).to redirect_to("/users/sign_in")
    end
  end

  describe "When authenticated #create" do
    include_context "basic_context"
    before(:each) do
      project
      sign_in user
    end

    let(:program) { create :program }

    let(:project) do
      project = build :project
      project.project_anchor = program.build_project_anchor
      project.save!
      user.program = program
      user.save!
      user.reload
      project
    end

    let(:valid_attributes) do
      {
        project_id:   project.id,
        entity_group: {
          external_reference: "external_reference",
          name:               "entity_group_name"
        }
      }
    end

    it "should verify that a project exist and is a draft" do
      stub_dhis_data_element_by_id(project, "external_reference")
      project.status = "published"
      project.save!
      post :create, params: {
        project_id:   project.id,
        entity_group: {
          external_reference: "external_reference"
        }
      }
      expect(response).to redirect_to("/setup/projects/#{project.id}")
      expect(flash[:failure]).to eq("Sorry this project has been published you can't edit it anymore")
    end

    it "should create missing entity group when correct info provided" do
      stub_dhis_data_element_by_id(project, "external_reference")

      post :create, params: valid_attributes

      expect(response).to redirect_to("/")
      expect(flash[:success]).to eq("Main entity group set !")
      group_entry = EntityGroup.all.last
      expect(group_entry.external_reference).to eq("external_reference")
      expect(group_entry.name).to eq("Clinic")
    end

    it "should update when correct info provided" do
      stub_dhis_data_element_by_id(project, "external_reference")
      stub_dhis_data_element_by_id(project, "new_external_reference")
      post :create, params: valid_attributes
      post :create, params: valid_attributes.merge(
        entity_group: {
          external_reference: "new_external_reference"
        }
      )
      expect(response).to redirect_to("/")
      expect(flash[:success]).to eq("Main entity group set !")

      group_entry = EntityGroup.all.last
      expect(group_entry.external_reference).to eq("new_external_reference")
      expect(group_entry.name).to eq("Clinic")
    end

    it "should validate presence" do
      stub_dhis_data_element_by_id(project, "external_reference")
      post :create, params: valid_attributes.merge(
        entity_group: {
          external_reference: " ",
          name:               ""
        }
      )
      expect(response).to redirect_to("/")
      expect(flash[:alert]).to eq("External reference can't be blank, Name can't be blank")
    end

    def stub_dhis_data_element_by_id(project, external_reference)
      stub_request(:get, "#{project.dhis2_url}/api/organisationUnitGroups/#{external_reference}")
        .to_return(status: 200, body: fixture_content(:dhis2, "organisationUnitGroups-findid.json"))
    end
  end
end
