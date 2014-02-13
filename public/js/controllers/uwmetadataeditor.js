var app = angular.module('uwmetadataeditorApp', ['ui.bootstrap', 'ajoslin.promise-tracker', 'metadataService', 'directoryService']);

app.controller('UwmetadataeditorCtrl', function($scope, MetadataService, DirectoryService, promiseTracker) {
    
	$scope.regex_pid = /^[a-zA-Z\-]+:[0-9]+$/;
	// use: <input ng-pattern="regex_identifier" ...
	
	// we will use this to track running ajax requests to show spinner
	$scope.loadingTracker = promiseTracker.register('loadingTracker');
	
	$scope.default_helptext = 'Loading tooltip content...';
	
	// used to disable the form and it's controls on save
	$scope.form_disabled = false;
	
    $scope.fields = [];
    $scope.languages = [];
    $scope.metadata_format_version = "";
    $scope.pid = '';
    $scope.alerts = [];        
    
    $scope.closeAlert = function(index) {
    	$scope.alerts.splice(index, 1);
    };
    
    $scope.getMetadataFormatVersion = function() {
        return $scope.metadata_format_version;
    };
    	
    $scope.getFieldsCount = function() {
        return $scope.fields.length;
    };
    
    $scope.init = function () {
    	//$scope.apply();
    };
    
    $scope.reset_values = function (node, default_value){
    	if(!default_value){
    		default_value = '';
    	}
    	node.ui_value = default_value;
    	node.loaded_ui_value = default_value;
    	node.value = default_value;
    	node.loaded_value = default_value;
    }
    
    $scope.curriculum_update_handler = function(curriculum_child_node){
		
    	if(!curriculum_child_node){
    		return;
    	}
    	
		var spl_namespace = 'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/organization/voc_spl/';
		var kennzahl_namespace = 'http://phaidra.univie.ac.at/XML/metadata/lom/V1.0/organization/voc_kennzahl/';
		
		// we don't want to update select-boxes when they are only being rendered    			
		if($scope.form.$pristine){
			return;
		}
		
		// find the next select-box and update it, and remove all the rest of them    			
		var curriculum_node = $scope.get_model_parent(null, $scope.fields, curriculum_child_node);
		
		// if 'none' is selected, just remove the remaining nodes
		if(!curriculum_child_node.ui_value){//kennzahl_namespace+'-100'){
			
			// this happens not only if user selected none but also
			// if we just added a new child and the watch was automatically
			// triggered again, that's why we check if there is actually something
			// to remove past this child node
			var i = 0;
			var current_change_index = 0;
			for (i = 0; i < curriculum_node.children.length; ++i) {
				if(curriculum_node.children[i] === curriculum_child_node){
    				current_change_index = i;
    				break;
    			}
			}
			if(current_change_index+1 < curriculum_node.children.length){
				curriculum_node.children.splice(current_change_index);
				curriculum_node.study_name = [];
			}
			return;
		}
		
		curriculum_node.study_name = [];
		var i = 0; 
		var spl = '';    			
		var ids = [];    			    		
		var current_change_index = 0;
    	for (i = 0; i < curriculum_node.children.length; ++i) {
    		var n = curriculum_node.children[i];
    		if(n.xmlname == 'spl'){
    			spl = n.ui_value.substring(spl_namespace.length);
    		}
    		if(n.xmlname == 'kennzahl'){
    			ids.push(n.ui_value.substring(kennzahl_namespace.length));    	    		
    		}
    		if(n === curriculum_child_node){
				current_change_index = i;
				break;
			}    	    		
    	}
    	    	
    	var promise = DirectoryService.getStudy(spl, ids, kennzahl_namespace);
    	$scope.loadingTracker.addPromise(promise);
    	promise.then(
    		function(response) { 
    			$scope.alerts = response.data.alerts;
    			
    			if(current_change_index == 0){
    				// we will reset the first kennzahl node and load new values
    				// the reset will cause the watch to trigger again (but that's ok)    	    				
    				angular.copy(response.data.terms, curriculum_node.children[1].vocabularies[0].terms);       	    				
    				$scope.reset_values(curriculum_node.children[1]);
    				curriculum_node.children.splice(2);
    			}else{
    				// copy first kennzahl node
        	    	var new_select = angular.copy(curriculum_node.children[1]);
        	    	if(response.data.terms.length == 0){
        	    		// we have probably reached the end of the definition
        	    		// try to get the study name
        	    		var promise1 = DirectoryService.getStudyName(spl, ids);
        	        	$scope.loadingTracker.addPromise(promise1);
        	        	promise1.then(
        	        		function(response) { 
        	        			$scope.alerts = response.data.alerts;
        	        			curriculum_node.study_name = response.data.study_name;
        	        		}
        	        		,function(response) {
        	        			$scope.alerts = response.data.alerts;
        	                	$scope.alerts.unshift({type: 'danger', msg: "Error code "+response.status});
        	                }
        	            );
        	    		return;
        	    	}
        	    	// put the result terms in
        	    	angular.copy(response.data.terms, new_select.vocabularies[0].terms);
        	    	// set value to 'none'
        	    	$scope.reset_values(new_select);
        	    	// update seq, not +1 because the current_change_index
        	    	// is the index in the curriculum_node array where there is also spl
        	    	// but seq starts at first kennzahl
        	    	new_select.data_order = current_change_index;
        	    	// remove all kennzahl nodes after the changed one
        	    	curriculum_node.children.splice(current_change_index+1);
        	    	// add the new node
	    			curriculum_node.children.push(new_select);
	    			// add the watch on it
	    			$scope.watched_curriculum_child_selectboxes.push(new_select);
    	    		$scope.$watch('watched_curriculum_child_selectboxes['+($scope.watched_curriculum_child_selectboxes.length-1)+']', $scope.curriculum_update_handler, true);	

    			}    	    		
    		}
    		,function(response) {
           		$scope.alerts = response.data.alerts;
           		$scope.alerts.unshift({type: 'danger', msg: "Error code "+response.status});
           	}
    	);
		
	}
    
    $scope.faculty_update_handler = function(faculty_node){
		
    	if(!faculty_node){
    		return;
    	}
    	
		// we don't want to update select-boxes when they are only being rendered    			
		if($scope.form.$pristine){
			return;
		}
		
		// find the department sibling and update it
		var orgassignment_node = $scope.get_model_parent(null, $scope.fields, faculty_node);
		// for orgassignment this is easy: 
		// orgassignment_node.children[0] is faculty;
		// orgassignment_node.children[1] is department;    			
		var faculty_id_uri = orgassignment_node.children[0].ui_value;
		var faculty_id_namespace = orgassignment_node.children[0].vocabularies[0].namespace;
		var department_namespace = orgassignment_node.children[1].vocabularies[0].namespace;
		var faculty_id = faculty_id_uri.substring(faculty_id_namespace.length);
			
		$scope.reset_values(orgassignment_node.children[1]);
		
		var promise = DirectoryService.getOrgUnits(faculty_id, department_namespace);
    	$scope.loadingTracker.addPromise(promise);
    	promise.then(
    		function(response) { 
    			$scope.alerts = response.data.alerts;    	    			
    			angular.copy(response.data.terms, orgassignment_node.children[1].vocabularies[0].terms);    	    			
    		}
    		,function(response) {
           		$scope.alerts = response.data.alerts;
           		$scope.alerts.unshift({type: 'danger', msg: "Error code "+response.status});
           	}
    	);
	};
    
    $scope.watched_faculty_selectboxes = [];
    $scope.watched_curriculum_child_selectboxes = [];
    
    $scope.load_init = function(){
    	
    	$scope.watched_faculty_selectboxes = [];
        $scope.watched_curriculum_child_selectboxes = [];        
    	
    	// find faculty select-box and study plan select-boxes
    	// and watch them, if these change, we need to update the
    	// next sibling select-box
    	if($scope.fields){
    		$scope.watch_cascaded($scope.fields);
    	}
    	
    	var i = 0; 	
    	for (i = 0; i < $scope.watched_faculty_selectboxes.length; ++i) {    		
    		$scope.$watch('watched_faculty_selectboxes['+i+']', $scope.faculty_update_handler, true);	
    	}
    	
    	for (i = 0; i < $scope.watched_curriculum_child_selectboxes.length; ++i) {    		
    		$scope.$watch('watched_curriculum_child_selectboxes['+i+']', $scope.curriculum_update_handler, true);	
    	}
    	
    };
    
     

    $scope.get_model_parent = function (parent, children, model) {
    	var i = 0; 	
    	for (i = 0; i < children.length; ++i) {
    		if(children[i] === model){
    			return parent;
    		}
    		if(children[i].children){
    			var ret_parent = $scope.get_model_parent(children[i], children[i].children, model);
    			if(ret_parent){
    				return ret_parent;
    			}
    		}
    	}
    }
    
    $scope.watch_cascaded = function (children) {    
    	var i = 0; 	
    	for (i = 0; i < children.length; ++i) {
    		// the cascaded select-boxes are always leafs
    		if(children[i].children){
    			$scope.watch_cascaded(children[i].children);
    		}else{
    			if(children[i].xmlname == 'faculty'){    
    				$scope.watched_faculty_selectboxes.push(children[i]);    				
    			}
    			if(children[i].xmlname == 'spl' || children[i].xmlname == 'kennzahl'){    
    				$scope.watched_curriculum_child_selectboxes.push(children[i]);    				
    			}
    		}
    		
    	}
    }
    
        
    $scope.save = function() {
    	var metadata_format_version = 1;
    	$scope.form_disabled = true;
    	var promise = MetadataService.saveUwmetadataToObject(metadata_format_version, $scope.pid, $scope.fields)
    	$scope.loadingTracker.addPromise(promise);
    	promise.then(
        	function(response) { 
        		$scope.alerts = response.data.alerts;
        		$scope.languages = [];
        		$scope.fields = [];    			
        		$scope.metadata_format_version = '';
        		$scope.form_disabled = false;
        	}
        	,function(response) {
           		$scope.alerts = response.data.alerts;
           		$scope.alerts.unshift({type: 'danger', msg: "Error code "+response.status});
           		$scope.form_disabled = false;
           	}
        );
    	        
    };
    
    $scope.resetEditor = function() {
    	$scope.alerts = [];
		$scope.languages = [];
		$scope.fields = [];    			
		$scope.metadata_format_version = '';
    };
    
    $scope.getUwmetadataTree = function(){
    	var metadata_format_version = 1;
    	$scope.resetEditor();
        var promise = MetadataService.getUwmetadataTree(metadata_format_version, pid);        
        $scope.loadingTracker.addPromise(promise);
        promise.then(
    		function(response) { 
    			$scope.alerts = response.data.alerts;
    			$scope.languages = response.data.languages;
    			$scope.fields = response.data.tree;    			
    			$scope.metadata_format_version = metadata_format_version;
    			$scope.load_init();
    		}
    		,function(response) {
           		$scope.alerts = response.data.alerts;
           		$scope.alerts.unshift({type: 'danger', msg: "Error code "+response.status});
           	}
    	);
    };
    
    // used to filter array of elements: if 'hidden' is set, the field will not be included in the array
    $scope.filterHidden = function(e)
    {
        return !e.hidden;        
    };
    
    $scope.loadObject = function(pid){
    	var metadata_format_version = 1;
    	$scope.resetEditor();
    	var promise = MetadataService.getUwmetadataFromObject(metadata_format_version, pid);
    	$scope.loadingTracker.addPromise(promise);
    	promise.then(
    		function(response) { 
    			$scope.alerts = response.data.alerts;
    			$scope.languages = response.data.languages;
    			$scope.fields = response.data.metadata;
    			$scope.load_init();
    		}
    		,function(response) {
           		$scope.alerts = response.data.alerts;
           		$scope.alerts.unshift({type: 'danger', msg: "Error code "+response.status});
           	}
    	);    	
    };
    
    $scope.canDelete = function(child){
    	var a = $scope.getContainingArray(this);  
    	var cnt = 0;
    	for (i = 0; i < a.length; ++i) {
    		if(a[i].xmlns == child.xmlns && a[i].xmlname == child.xmlname){
    			cnt++;
    		}
    	}
    	return cnt > 1;
    }
    
    $scope.addNewElement = function(child){    	    	
    	// array of elements to which we are going to insert
    	var arr = $scope.getContainingArray(this);    	
    	// copy the element
    	var tobesistr = angular.copy(child);    	
    	// get index of the current element in this array
    	var idx = angular.element.inArray(child, arr); // we loaded jQuery before angular so angular.element should equal jQuery
    	// increment order of the new element (we are appending to the current one)
    	// and also all the next elements
    	// but only if the elements are actually ordered
    	if(child.ordered){
    		tobesistr.data_order++;
    		var i;
        	for (i = idx+1; i < arr.length; ++i) {
        		// update only elements of the same type
        		if(arr[i].xmlns == child.xmlns && arr[i].xmlname == child.xmlname){
        			arr[i].data_order++;
        		}
        	}
    	}    	
    	// insert into array at specified index, angular will sort the rest out
    	arr.splice(idx+1, 0, tobesistr);    
    	
    	// register watches! (eg if the new element is orgassignment or curriculum)
    	if(tobesistr.children){
    		if(tobesistr.xmlname == 'curriculum'){
    			// leave just spl and one kennzahl node
    			tobesistr.children.splice(2);
    			// reset the kennzahl node
    			$scope.reset_values(tobesistr.children[1]);
    			tobesistr.study_name = [];
    		}
    		var i = 0;
	    	for (i = 0; i < tobesistr.children.length; ++i) {
	    		var n = tobesistr.children[i];
	    		// the cascaded select-boxes are always leafs
	    		if(n.xmlname == 'faculty'){  	    			
	    			$scope.watched_faculty_selectboxes.push(n);
	    			$scope.$watch('watched_faculty_selectboxes['+($scope.watched_faculty_selectboxes.length-1)+']', $scope.faculty_update_handler, true);
	    		}
	    		if(n.xmlname == 'spl' || n.xmlname == 'kennzahl'){	    			
	    			$scope.reset_values(n);	    			
	    			$scope.watched_curriculum_child_selectboxes.push(n); 
	    			$scope.$watch('watched_curriculum_child_selectboxes['+($scope.watched_curriculum_child_selectboxes.length-1)+']', $scope.curriculum_update_handler, true);
	    		}	    			    		
	    	}
    	}
    }
    
    $scope.deleteElement = function(child){    	
    	// array of elements where we are going to delete
    	var arr = $scope.getContainingArray(this);	    	    	
    	// get index of the current element in this array
    	var idx = angular.element.inArray(child, arr); // we loaded jQuery before angular so angular.element should equal jQuery
    	// decrement data_order of remaining elements
    	if(child.ordered){
	    	var i;
	    	for (i = idx+1; i < arr.length; ++i) {
	    		// update only elements of the same type
        		if(arr[i].xmlns == child.xmlns && arr[i].xmlname == child.xmlname){
        			arr[i].data_order--;
        		}
	    	}
    	}
    	// delete
    	arr.splice(idx, 1);    
    }
    
    // black magic here...
    $scope.getContainingArray = function(scope){
    	// this works for normal fields
    	var arr = scope.$parent.$parent.$parent.field.children;    	
    	// this for blocks
    	if(scope.$parent.$parent.$parent.$parent.$parent.child){
    		if(scope.$parent.$parent.$parent.$parent.$parent.child.children){
    			arr = scope.$parent.$parent.$parent.$parent.$parent.child.children;
    		}
    	}    	
    	// and this for fields in blocks
    	if(scope.$parent.$parent.$parent.$parent.$parent.$parent.child){
    		if(scope.$parent.$parent.$parent.$parent.$parent.$parent.child.children){
    			arr = scope.$parent.$parent.$parent.$parent.$parent.$parent.child.children;
    		}
    	}
    	return arr;
    }
    
    Array.prototype.move = function(from, to) {
        this.splice(to, 0, this.splice(from, 1)[0]);
    };
    
    $scope.upElement = function(child){
    	// array of elements which we are going to rearrange
    	var arr = $scope.getContainingArray(this);
    	// get index of the current element in this array
    	var idx = angular.element.inArray(child, arr);
    	
    	// update the data_order property
    	if(child.ordered){
	    	child.data_order--;
	    	// only if it's the same type (should be always true
	    	// because we are checking this in canUpElement)
    		if(arr[idx-1].xmlns == child.xmlns && arr[idx-1].xmlname == child.xmlname){
    			arr[idx-1].data_order++;
    		}
    	}
    	
    	// move to index--
    	if(idx > 0){
    		arr.move(idx, idx-1);
    	}    	
    }

    $scope.downElement = function(child){
    	// array of elements which we are going to rearrange
    	var arr = $scope.getContainingArray(this);
    	// get index of the current element in this array
    	var idx = angular.element.inArray(child, arr);
    	
    	// update the data_order property
    	if(child.ordered){
	    	child.data_order++;
	    	// only if it's the same type (should be always true
	    	// because we are checking this in canDownElement)
    		if(arr[idx+1].xmlns == child.xmlns && arr[idx+1].xmlname == child.xmlname){
    			arr[idx+1].data_order--;
    		}
    	}
    	
    	// move to index++
    	arr.move(idx, idx+1);    	
    }
    
    $scope.canUpElement = function(child){
    	return child.ordered && (child.data_order > 0);
    }

    $scope.canDownElement = function(child){
    	
    	if(!child.ordered){ return false; }
    	
    	// this array can contain also another type of elements
    	// but we only order the same type, so find if there is
    	// an element of the same type with higher data_ordered
    	var arr = $scope.getContainingArray(this);
    	
	    var i;
	    for (i = 0; i < arr.length; ++i) {
	        if(arr[i].data_order > child.data_order){
	        	return true;
	        }
	    }
    	
	    return false;

    }
    
    // just for debug
    $scope.getIndex = function(child){
    	// array of elements which we are going to rearrange
    	var arr = $scope.getContainingArray(this);
    	// get index of the current element in this array
    	return angular.element.inArray(child, arr);
    }
    
});

app.directive('phaidraDuration', function() {
      
      function link(scope, element, attrs) {
    	  scope.durationObject = {  hours: '', minutes: '', seconds: ''};
    	  scope.regex_duration = /^[0-9][0-9]*$/;
    
          scope.$watch('duration', function(value) {        	  
        	  if(value){
	        	// format: PT99H12M13S
        		var regex = /^PT([0-9][0-9]*)H/g;
        		var match = regex.exec(value.ui_value);
	            var hours = match ? match[1] : '';
	            
	            regex = /H([0-9][0-9]*)M/g;
        		match = regex.exec(value.ui_value);
	            var minutes = match ? match[1] : '';
	            
	            regex = /M([0-9][0-9]*)S$/g;
        		match = regex.exec(value.ui_value);
	            var seconds = match ? match[1] : '';
	           
		        scope.durationObject.hours = hours ? hours : '';
		        scope.durationObject.minutes = minutes ? minutes : '';
		        scope.durationObject.seconds = seconds ? seconds : '';
	           
        	  }
          }, true);
     
          scope.$watch('durationObject', function(value) { 
        	  //alert(scope.durationObject.hours+':'+scope.durationObject.minutes+':'+scope.durationObject.seconds);
        	  if(value && (scope.durationObject.hours || scope.durationObject.minutes || scope.durationObject.seconds)){
        		  scope.duration.ui_value = 'PT' + (scope.durationObject.hours ? scope.durationObject.hours : '') + 'H' + (scope.durationObject.minutes ? scope.durationObject.minutes : '') + 'M' + (scope.durationObject.seconds ? scope.durationObject.seconds : '') + 'S';
        		  scope.duration.value = 'PT' + (scope.durationObject.hours ? scope.durationObject.hours : '00') + 'H' + (scope.durationObject.minutes ? scope.durationObject.minutes : '00') + 'M' + (scope.durationObject.seconds ? scope.durationObject.seconds : '00') + 'S';
        	  }else{
        		  scope.duration.ui_value = '';
        		  scope.duration.value = '';
        	  }
          }, true);
          
        }
     
        return {
          restrict: 'E',
          link: link,
          replace: true,
          templateUrl: '/views/directives/duration.html',
          scope: {
        	  duration: '=duration'
            },
        };
});

// lazy binding
(function($){
    $.fn.lazybind = function(event, fn, timeout, abort){
        var timer = null;
        $(this).bind(event, function(e){
            var ev = e;
            timer = setTimeout(function(){
                fn(ev);
            }, timeout);
        });
        if(abort == undefined){
            return;
        }
        $(this).bind(abort, function(){
            if(timer != null){
                clearTimeout(timer);
            }
        });
    };
})(jQuery);

// load tooltip content on demand
app.directive('phaidraHelp', function($http, $timeout) {
	 return {
	  restrict: 'A', 

	  link: function(scope, element, attr) {
	  
	      // the tooltip is shown after some delay
	      // and we also don't want to load the content
		  // when user just crossed the field with a mouse
		  // so we are going to load it on mouseover, but only
		  // if user stays hier a while (see, if mouseout before, it will be cancelled)
		  // BUT, we want the content to be loaded before the tooltip shows
		  // otherwise it will be wrong positioned because of the changed content
		  // (and correctly positioned only on second hover)
		  // + we need to call $scope.$apply
		  element.lazybind('mouseover',function(e) {
			 
			  // this will make the tooltip realize it has a new content
			  // so if the new content is already there, it will be correctly positioned
			  scope.$apply(function(e) {
				  
				  if(attr['loaded']){
					  return;			  
				  }
				 
		          var promise = $http({
			          method  : 'GET',
			          url     : '/help/tooltip',
			          params  : { id: attr['phaidraHelpId']  }
			      });        
			      scope.loadingTracker.addPromise(promise);
			      promise.then(
			  		function(response) { 	  		
			  			
			  			attr.$set('tooltipHtmlUnsafe', response.data.content);
			  			attr.$set('loaded', true);
			  			
			   		}
			   		,function(response) {
			   			attr.$set('tooltipHtmlUnsafe', "Failed to load tooltip");
			       	}
			   	  );
		      
			  });
		  }, 1000, 'mouseout' );
	   }
	 }
});


