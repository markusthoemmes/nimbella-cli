load ../test_setup.bash

teardown() {
	delete_package "test-ie-admin"
	delete_package "test-ie-printer"
}

@test "deploy project excluding folder " {
	run $NIM project deploy $BATS_TEST_DIRNAME --exclude test-ie-admin
	assert_success
	assert_output --partial 'test-ie-printer'
	refute_output --partial 'test-ie-admin'
}

@test "deploy project including folder " {
	run $NIM project deploy $BATS_TEST_DIRNAME --include test-ie-printer/notify
	assert_success
	assert_output --partial 'test-ie-printer/notify'
	refute_output --partial 'test-ie-printer/update'
	refute_output --partial 'test-ie-printer/list'
	refute_output --partial 'test-ie-printer/get'
	refute_output --partial 'test-ie-printer/create'
	refute_output --partial 'test-ie-admin'
}

@test "deploy project with multiple include/excludes" {
	run $NIM project deploy $BATS_TEST_DIRNAME --include test-ie-admin/,test-ie-printer --exclude test-ie-printer/notify,test-ie-printer/update
	assert_success
	assert_output --partial 'test-ie-admin'
	assert_output --partial 'test-ie-printer/get'
	assert_output --partial 'test-ie-printer/create'
	assert_output --partial 'test-ie-printer/list'
	refute_output --partial 'test-ie-printer/notify'
	refute_output --partial 'test-ie-printer/update'
}
