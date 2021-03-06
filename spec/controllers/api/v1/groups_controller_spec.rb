require 'spec_helper'

shared_examples_for 'api group user with reader rights' do
  it 'should be able to perform members action' do
    get :members, id: @group.id, format: :json
    response.should be_success
  end
  it_should_behave_like 'api group user with show rights'
end

shared_examples_for 'api group user with show rights' do
  it 'should be able to perform show action' do
    get :show, id: @group.id, format: :json
    response.should be_success
  end

  it 'should be able to perform index action' do
    get :index, format: :json
    response.should be_success
  end
end

shared_examples_for 'api group user without reader rights' do
  it 'should not be able to perform members action' do
    get :members, id: @group.id, format: :json
    response.should_not be_success
  end
end

shared_examples_for 'api group user with admin rights' do

  context 'api group user with update rights' do
    before do
      put :update, group: { description: 'new description' }, id: @group.id, format: :json
    end

    it 'should be able to perform update action' do
      response.should be_success
    end
    it 'ensures that group has been updated' do
      @group.reload
      @group.description.should == 'new description'
    end
  end

  context 'api group user with add_member rights' do
    let(:member) { FactoryGirl.create(:user) }
    before do
      put :add_member, member_id: member.id, id: @group.id, format: :json
    end

    it 'should be able to perform add_member action' do
      response.should be_success
    end
    it 'ensures that new member has been added to group' do
      @group.members.should include(member)
    end
  end

  context 'api group user with remove_member rights' do
    let(:member) { FactoryGirl.create(:user) }
    before do
      @group.add_member(member)
      delete :remove_member, member_id: member.id, id: @group.id, format: :json
    end

    it 'should be able to perform remove_member action' do
      response.should be_success
    end
    it 'ensures that member has been removed from group' do
      @group.members.should_not include(member)
    end
  end

  context 'api group user with update_member rights' do
    let(:member) { FactoryGirl.create(:user) }
    before do
      @group.add_member(member)
      put :update_member, member_id: member.id, role: 'reader', id: @group.id, format: :json
    end

    it 'should be able to perform update_member action' do
      response.should be_success
    end
    it 'ensures that member role has been updated in group' do
      @group.actors.where(actor_id: member, actor_type: 'User').first.
        role.should == 'reader'
    end
  end
end

shared_examples_for 'api group user with owner rights' do
  context 'api group user with destroy rights' do
    it 'should be able to perform destroy action' do
      delete :destroy, id: @group.id, format: :json
      response.should be_success
    end
    it 'ensures that group has been destroyed' do
      lambda { delete :destroy, id: @group.id, format: :json }.should change{ Group.count }.by(-1)
    end
  end
end

shared_examples_for 'api group user without admin rights' do
  context 'api group user without update_member rights' do
    let(:member) { FactoryGirl.create(:user) }
    before do
      @group.add_member(member)
      put :update_member, member_id: member.id, role: 'reader', id: @group.id, format: :json
    end

    it 'should not be able to perform update_member action' do
      response.should_not be_success
    end
    it 'ensures that member role has not been updated in group' do
      @group.actors.where(actor_id: member, actor_type: 'User').first.
        role.should_not == 'reader'
    end
  end

  context 'api group user without update rights' do
    before do
      put :update, group: { description: 'new description' }, id: @group.id, format: :json
    end

    it 'should not be able to perform update action' do
      response.should_not be_success
    end
    it 'ensures that platform has not been updated' do
      @group.reload
      @group.description.should_not == 'new description'
    end
  end

  context 'api group user without add_member rights' do
    let(:member) { FactoryGirl.create(:user) }
    before do
      put :add_member, member_id: member.id, id: @group.id, format: :json
    end

    it 'should not be able to perform add_member action' do
      response.should_not be_success
    end
    it 'ensures that new member has not been added to group' do
      @group.members.should_not include(member)
    end
  end

  context 'api group user without remove_member rights' do
    let(:member) { FactoryGirl.create(:user) }
    before do
      @group.add_member(member)
      delete :remove_member, member_id: member.id, id: @group.id, format: :json
    end

    it 'should be able to perform update action' do
      response.should_not be_success
    end
    it 'ensures that member has not been removed from group' do
      @group.members.should include(member)
    end
  end

end

shared_examples_for 'api group user without owner rights' do
  context 'api group user without destroy rights' do
    it 'should not be able to perform destroy action' do
      delete :destroy, id: @group.id, format: :json
      response.should_not be_success
    end
    it 'ensures that group has not been destroyed' do
      lambda { delete :destroy, id: @group.id, format: :json }.should_not change{ Group.count }
    end
  end
end

describe Api::V1::GroupsController do
  before do
    stub_symlink_methods

    @group = FactoryGirl.create(:group)
    @user = FactoryGirl.create(:user)
  end

  context 'for guest' do

    it "should not be able to perform index action" do
      get :index, format: :json
      response.status.should == 401
    end

    it "should not be able to perform show action", :anonymous_access  => false do
      get :show, id: @group.id, format: :json
      response.status.should == 401
    end

    it "should be able to perform show action", :anonymous_access  => true do
      get :show, id: @group.id, format: :json
      response.should be_success
    end

    context 'api group user without create rights' do
      let(:params) { {group: {uname: 'test_uname'}} }
      it 'should not be able to perform create action' do
        post :create, params, format: :json
        response.should_not be_success
      end
      it 'ensures that group has not been created' do
        lambda { post :create, params, format: :json }.should_not change{ Group.count }
      end
    end

    it_should_behave_like 'api group user without reader rights'
    it_should_behave_like 'api group user without admin rights'
    it_should_behave_like 'api group user without owner rights'
  end

  context 'for global admin' do
    before do
      @admin = FactoryGirl.create(:admin)
      http_login(@admin)
    end

    it_should_behave_like 'api group user with reader rights'
    it_should_behave_like 'api group user with admin rights'
    it_should_behave_like 'api group user with owner rights'
  end

  context 'for owner user' do
    before do
      @group = FactoryGirl.create(:group, owner: @user)
      http_login(@user)
    end

    it_should_behave_like 'api group user with reader rights'
    it_should_behave_like 'api group user with admin rights'
    it_should_behave_like 'api group user with owner rights'
  end

  context 'for admin user' do
    before do
      @group.add_member(@user)
      http_login(@user)
    end

    it_should_behave_like 'api group user with reader rights'
    it_should_behave_like 'api group user with admin rights'
    it_should_behave_like 'api group user without owner rights'
  end

  context 'for simple user' do
    before do
      http_login(@user)
    end

    it_should_behave_like 'api group user with show rights'
    it_should_behave_like 'api group user without reader rights'
    it_should_behave_like 'api group user without admin rights'
    it_should_behave_like 'api group user without owner rights'
  end
end
