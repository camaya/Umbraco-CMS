(function() {
    'use strict';

    function Variations(iconHelper) {

        function link(scope, el, attr, ctrl) {

            scope.newVariation = {};

            scope.segments = [
                {
                    name: "Mobile"
                },
                {
                    name: "Front-end developer"
                },
                {
                    name: "back-end developer"
                }
            ];

            scope.showNewVariation = function(language) {
                language.showNewVariation = true;
            };

            scope.hideNewVariation = function(language) {
                language.showNewVariation = false;
            };

            scope.toggleEditVariation = function(selectedVariation) {
                selectedVariation.editVariation = !selectedVariation.editVariation;
            };

            scope.createNewVariation = function(newVariation, language) {
                language.variations.unshift(newVariation);
                language.showNewVariation = false;
                scope.newVariation = {
                    name: "",
                    description: "",
                    segments: []
                };
            };

            scope.saveVariation = function(variation, language) {
                variation.editVariation = false;
            };

            scope.deleteVariation = function(variation, language) {
                var index  = language.variations.indexOf(variation);
                language.variations.splice(index, 1);
            };

            scope.hideEditVariation = function(variation) {
                variation.editVariation = false;
            };

        }

        var directive = {
            restrict: 'E',
            replace: true,
            templateUrl: 'views/components/umb-variations.html',
            scope: {
                variations: "=",
                onClickVariation: "=",
                onSaveVariation: "=",
                onCloneVariation: "=",
                onDeleteVariation: "="
            },
            link: link
        };

        return directive;
    }

    angular.module('umbraco.directives').directive('umbVariations', Variations);

})();