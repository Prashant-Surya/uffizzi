# frozen_string_literal: true

require 'test_helper'

class UffizziCore::Api::Cli::V1::Projects::ComposeFilesControllerTest < ActionController::TestCase
  setup do
    @admin = create(:user, :with_personal_account)
    @account = @admin.personal_account
    @project = create(:project, :with_members, account: @account, members: [@admin])
    @compose_file = create(:compose_file, project: @project, added_by: @admin)
    image = generate(:image)
    image_namespace, image_name = image.split('/')
    target_branch = generate(:branch)
    repo_attributes = attributes_for(
      :repo,
      :docker_hub,
      namespace: image_namespace,
      name: image_name,
      branch: target_branch,
    )
    container_attributes = attributes_for(
      :container,
      :with_public_port,
      image: image,
      tag: target_branch,
      receive_incoming_requests: true,
      repo_attributes: repo_attributes,
    )
    template_payload = {
      containers_attributes: [container_attributes],
    }
    create(:template, :compose_file_source, compose_file: @compose_file, project: @project, added_by: @admin, payload: template_payload)
  end

  test '#show - admin gets compose file' do
    sign_in @admin

    params = { project_slug: @project.slug }

    get :show, params: params, format: :json

    assert_response :success
  end

  test '#show - returns 404 if compose file does not exist' do
    sign_in @admin

    @compose_file.destroy!

    params = { project_slug: @project.slug }

    get :show, params: params, format: :json

    error_message = JSON.parse(response.body, symbolize_names: true)[:errors][:title].first

    assert_response :not_found
    assert_equal('UffizziCore::ComposeFile Not Found', error_message)
  end

  test '#create - docker compose file' do
    sign_in @admin

    @compose_file.destroy!
    base_attributes = attributes_for(:compose_file).slice(:source, :path)
    file_content = File.read('test/fixtures/files/uffizzi-compose-vote-app-docker.yml')
    encoded_content = Base64.encode64(file_content)
    compose_file_attributes = base_attributes.merge(content: encoded_content, repository_id: nil)
    dependency = {
      path: 'configs/vote.conf',
      source: 'vote.conf',
      content: json_fixture('files/compose_dependencies/configs/vote_conf.json')[:content],
      use_kind: UffizziCore::ComposeFile::DependenciesService::DEPENDENCY_CONFIG_USE_KIND,
    }

    stub_dockerhub_repository_any

    params = {
      project_slug: @project.slug,
      compose_file: compose_file_attributes,
      dependencies: [dependency],
    }

    differences = {
      -> { UffizziCore::ComposeFile.main.count } => 1,
      -> { UffizziCore::Template.with_creation_source(UffizziCore::Template.creation_source.compose_file).count } => 1,
    }

    assert_difference differences do
      post :create, params: params, format: :json
    end

    assert_response :success
  end

  test '#create - main compose file when already exists' do
    sign_in @admin

    base_attributes = attributes_for(:compose_file).slice(:source, :path)
    file_content = File.read('test/fixtures/files/test-compose-success-without-dependencies.yml')
    encoded_content = Base64.encode64(file_content)
    stub_dockerhub_repository_any
    compose_file_attributes = base_attributes.merge(content: encoded_content, repository_id: nil)

    params = {
      project_slug: @project.slug,
      compose_file: compose_file_attributes,
      dependencies: [],
    }

    differences = {
      -> { UffizziCore::ComposeFile.main.count } => 0,
      -> { UffizziCore::Template.with_creation_source(UffizziCore::Template.creation_source.compose_file).count } => 0,
    }

    assert_difference differences do
      post :create, params: params, format: :json
    end

    assert_response :success
  end

  test '#create - check amazon ecr creation' do
    sign_in @admin

    project = create(:project, :with_members, account: @account, members: [@admin])
    create(:credential, :amazon, account: @account)

    base_attributes = attributes_for(:compose_file).slice(:source, :path)
    file_content = File.read('test/fixtures/files/uffizzi-compose-amazon.yml')
    encoded_content = Base64.encode64(file_content)
    compose_file_attributes = base_attributes.merge(content: encoded_content, repository_id: nil)

    differences = {
      -> { UffizziCore::Template.count } => 1,
      -> { UffizziCore::ComposeFile.count } => 1,
    }

    params = {
      project_slug: project.slug,
      compose_file: compose_file_attributes,
      dependencies: [],
    }

    assert_difference differences do
      post :create, params: params, format: :json
    end

    assert_response :success
  end

  test '#create - check github registry creation' do
    sign_in @admin

    project = create(:project, :with_members, account: @account, members: [@admin])
    create(:credential, :github_container_registry, account: @account)
    create(:credential, :docker_hub, account: @account)

    @compose_file.destroy!
    base_attributes = attributes_for(:compose_file).slice(:source, :path)
    content = json_fixture('files/github/compose_files/hello_world_compose_github_container_registry.json')[:content]
    compose_file_attributes = base_attributes.merge(content: content)

    differences = {
      -> { UffizziCore::Template.count } => 1,
      -> { UffizziCore::ComposeFile.count } => 1,
    }

    params = {
      project_slug: project.slug,
      compose_file: compose_file_attributes,
      dependencies: [],
    }

    assert_difference differences do
      post :create, params: params, format: :json
    end

    assert_response :success
  end

  test '#create - compose file with volumes' do
    sign_in @admin

    @compose_file.destroy!
    base_attributes = attributes_for(:compose_file).slice(:source, :path)
    file_content = File.read('test/fixtures/files/compose_files/compose_with_volumes.yml')
    stub_dockerhub_repository_any
    encoded_content = Base64.encode64(file_content)
    compose_file_attributes = base_attributes.merge(content: encoded_content, repository_id: nil)

    params = {
      project_slug: @project.slug,
      compose_file: compose_file_attributes,
      dependencies: [],
    }

    differences = {
      -> { UffizziCore::ComposeFile.main.count } => 1,
      -> { UffizziCore::Template.with_creation_source(UffizziCore::Template.creation_source.compose_file).count } => 1,
    }

    assert_difference differences do
      post :create, params: params, format: :json
    end

    assert_response :success
  end

  test '#create - with yaml aliases' do
    sign_in @admin

    @compose_file.destroy!
    stub_dockerhub_repository('library', 'nginx')
    base_attributes = attributes_for(:compose_file).slice(:source, :path)
    file_content = File.read('test/fixtures/files/uffizzi-compose-with_alias.yml')
    encoded_content = Base64.encode64(file_content)
    compose_file_attributes = base_attributes.merge(content: encoded_content, repository_id: nil)
    dependency = {
      path: 'configs/vote.conf',
      source: 'vote.conf',
      content: json_fixture('files/compose_dependencies/configs/vote_conf.json')[:content],
      use_kind: UffizziCore::ComposeFile::DependenciesService::DEPENDENCY_CONFIG_USE_KIND,
    }

    params = {
      project_slug: @project.slug,
      compose_file: compose_file_attributes,
      dependencies: [dependency],
    }

    differences = {
      -> { UffizziCore::ComposeFile.main.count } => 1,
      -> { UffizziCore::Template.with_creation_source(UffizziCore::Template.creation_source.compose_file).count } => 1,
    }

    assert_difference differences do
      post :create, params: params, format: :json
    end

    assert_response :success
  end

  test '#create - string command' do
    sign_in @admin

    @compose_file.destroy!
    base_attributes = attributes_for(:compose_file).slice(:source, :path)
    file_content = File.read('test/fixtures/files/uffizzi-compose-vote-app-with-command-as-string.yml')
    encoded_content = Base64.encode64(file_content)
    compose_file_attributes = base_attributes.merge(content: encoded_content, repository_id: nil)

    stub_dockerhub_repository_any

    params = {
      project_slug: @project.slug,
      compose_file: compose_file_attributes,
      dependencies: [],
    }

    differences = {
      -> { UffizziCore::ComposeFile.main.count } => 1,
      -> { UffizziCore::Template.with_creation_source(UffizziCore::Template.creation_source.compose_file).count } => 1,
    }

    assert_difference differences do
      post :create, params: params, format: :json
    end

    assert_response :success
    template = UffizziCore::Template.last
    assert_equal('["postgres", "-c", "jit=off"]', template.payload['containers_attributes'].first['command'])
  end

  test '#destroy - deletes compose file' do
    sign_in @admin

    params = { project_slug: @project.slug }

    differences = {
      -> { UffizziCore::ComposeFile.count } => -1,
      -> { UffizziCore::Template.with_creation_source(UffizziCore::Template.creation_source.compose_file).count } => -1,
    }

    assert_difference differences do
      delete :destroy, params: params, format: :json
    end

    assert_response :no_content
  end

  test '#destroy - when compose_file not found' do
    sign_in @admin

    @compose_file.destroy!
    params = { project_slug: @project.slug }

    delete :destroy, params: params, format: :json

    error_message = JSON.parse(response.body, symbolize_names: true)[:errors][:title].first

    assert_response :not_found
    assert_equal('UffizziCore::ComposeFile Not Found', error_message)
  end
end
