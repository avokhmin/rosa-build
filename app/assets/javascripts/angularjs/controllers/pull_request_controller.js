RosaABF.controller('PullRequestController', function($scope, $http, ApiPullRequest, ApiProject, DateTimeFormatter) {

  $scope.project_id       = null;
  $scope.project_resource = null;

  $scope.serial_id        = null;
  $scope.pull             = null;
  $scope.pull_resource    = null;

  $scope.merged_at  = null;
  $scope.closed_at  = null;
  $scope.branch     = null;

  $scope.can_delete_branch  = false;

  $scope.init = function(project_id, serial_id) {
    $scope.project_id = project_id;
    $scope.serial_id  = serial_id;
    $scope.getPullRequest();
  }

  $scope.getPullRequest = function() {
    $scope.pull_resource = ApiPullRequest.resource.get(
      {project_id: $scope.project_id, serial_id: $scope.serial_id},
      function(results) {
        $scope.pull = results.pull_request;
        if ($scope.pull.merged_at) { $scope.merged_at = DateTimeFormatter.utc($scope.pull.merged_at); }
        if ($scope.pull.closed_at) { $scope.closed_at = DateTimeFormatter.utc($scope.pull.closed_at); }
      }
    );
  }

  $scope.getBranch = function() {
    if (!$scope.project_resource) {
      $scope.project_resource = ApiProject.resource.get({id: $scope.project_id});
    }
    $scope.project_resource.$refs({id: $scope.project_id}, function(results) {
      _.each(results.refs_list, function(ref){
        var result = new ProjectRef(ref);
        if (!result.isTag && result.ref == $scope.pull.from_ref.ref) {
          $scope.branch = result;
          return true;
        }
      });
    });
  }

  $scope.reopen = function() {
    $scope.pull.status = 'reopen';
    $scope.pull_resource.$update(function() {
      $scope.getPullRequest();
    });
  }

  $scope.close = function() {
    $scope.pull.status = 'close';
    $scope.pull_resource.$update(function() {
      $scope.getPullRequest();
    });
  }

  $scope.merge = function() {
    $scope.pull_resource.$merge(function() {
      $scope.getPullRequest();
    });
  }

  $scope.deleteBranch = function() {
    $scope.project_resource.$delete_branch($scope.branch_params(), function() {
      $scope.branch = null; 
    });
  }

  $scope.restoreBranch = function() {
    $scope.project_resource.$restore_branch($scope.branch_params(), function() {
      $scope.getBranch();
    });
  }

  $scope.branch_params = function() {
    var project = $scope.pull.from_ref.project;
    return {
      owner:    project.fullname.replace(/\/.*/, ''),
      project:  project.name,
      ref:      $scope.pull.from_ref.ref,
      sha:      $scope.pull.from_ref.sha
    }
  }

});