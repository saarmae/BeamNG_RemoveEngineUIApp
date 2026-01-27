(function() {
  'use strict';

  angular.module('beamng.apps')
    .directive('removeEngine', ['$interval', function($interval) {
      return {
        template:
          '<div class="remove-engine-app" layout="column" layout-align="start stretch" style="width:100%;height:100%;padding:12px;box-sizing:border-box;font-family:\'Space Grotesk\',\'Segoe UI\',sans-serif;">' +
            '<div layout="row" layout-align="space-between center" style="gap:12px;flex-wrap:wrap;">' +
              '<div style="flex:1 1 200px;min-width:160px;">' +
                '<div style="font-size:16px;font-weight:600;color:#f2f2f2;letter-spacing:0.5px;">Remove Engine</div>' +
                '<div style="font-size:13px;color:#c8d1d9;margin-top:4px;">{{state.vehicleName}}</div>' +
                '<div style="font-size:12px;color:#8fa2b5;margin-top:6px;">Status: <span style="color:#f6f6f6;">{{state.statusText}}</span></div>' +
                '<div style="font-size:12px;color:#8fa2b5;margin-top:2px;">Slot: <span style="color:#f6f6f6;">{{state.slotLabel || "Unavailable"}}</span></div>' +
              '</div>' +
              '<md-button class="md-raised" style="min-width:190px;height:48px;background:{{state.buttonColor}};color:#0e1116;font-size:14px;font-weight:600;text-transform:uppercase;letter-spacing:0.8px;"' +
                ' ng-click="setEngineEmpty()" ng-disabled="!state.canRemove || state.busy" md-no-ink>' +
                '{{state.buttonLabel}}' +
              '</md-button>' +
            '</div>' +
            '<div ng-if="state.error" style="margin-top:10px;padding:6px 10px;border-radius:4px;background:#471b1d;color:#ffb4b4;font-size:12px;">{{state.error}}</div>' +
            '<div ng-if="!state.error && state.message" style="margin-top:10px;padding:6px 10px;border-radius:4px;background:#1f3b2b;color:#b7f0c2;font-size:12px;">{{state.message}}</div>' +
          '</div>',
        replace: true,
        restrict: 'EA',
        link: function(scope) {
          scope.state = {
            vehicleId: null,
            vehicleName: 'No vehicle detected',
            slotLabel: null,
            statusText: 'Spawn a vehicle to continue',
            buttonLabel: 'Set Engine To Empty',
            buttonColor: '#b5c9d6',
            canRemove: false,
            isEmpty: true,
            busy: false,
            error: null,
            message: null
          };

          function applyButtonState() {
            if (scope.state.busy) {
              scope.state.buttonLabel = 'Working...';
              scope.state.buttonColor = '#5a7693';
              return;
            }
            if (!scope.state.canRemove) {
              scope.state.buttonColor = '#5a626b';
              scope.state.buttonLabel = scope.state.isEmpty ? 'Already Empty' : 'Unavailable';
            } else {
              scope.state.buttonColor = '#7ed68c';
              scope.state.buttonLabel = 'Set Engine To Empty';
            }
          }

          function setError(message) {
            scope.state.error = message;
            scope.state.message = null;
          }

          function setMessage(message) {
            scope.state.message = message;
            scope.state.error = null;
          }

          function parseResult(raw) {
            if (!raw || raw === 'null') {
              return {};
            }
            if (angular.isObject(raw)) {
              return raw;
            }
            if (typeof raw === 'string') {
              try {
                return JSON.parse(raw);
              } catch (e) {
                console.error('RemoveEngine: unable to parse payload', e, raw);
              }
            }
            return {};
          }

          function updateStateFromPayload(data) {
            if (!data.success) {
              scope.state.vehicleId = null;
              scope.state.vehicleName = 'No vehicle detected';
              scope.state.slotLabel = null;
              scope.state.statusText = data.message || 'Spawn a vehicle to continue';
              scope.state.canRemove = false;
              scope.state.isEmpty = false;
              if (data.message) {
                setMessage(data.message);
              } else {
                scope.state.message = null;
                scope.state.error = null;
              }
              return;
            }

            var slotId = data.slotId || null;
            var slotLabel = data.slotLabel || slotId;
            var partName = data.partName || '';
            scope.state.vehicleId = data.vehicleId;
            scope.state.vehicleName = data.vehicleName || 'Active vehicle';
            scope.state.slotLabel = slotLabel;
            scope.state.isEmpty = !!data.isEmpty;

            if (!slotId) {
              scope.state.statusText = 'No engine slot detected';
              scope.state.canRemove = false;
            } else if (scope.state.isEmpty) {
              scope.state.statusText = 'Engine already empty';
              scope.state.canRemove = false;
            } else {
              scope.state.statusText = partName ? ('Installed: ' + partName) : 'Engine installed';
              scope.state.canRemove = true;
            }

            if (data.message) {
              setMessage(data.message);
            } else {
              scope.state.message = null;
              scope.state.error = null;
            }
          }

          scope.refreshState = function() {
            return bngApi.engineLua('return extensions.core_RemoveEngine.getEngineSlotInfo()')
              .then(function(result) {
                var data = parseResult(result);
                updateStateFromPayload(data);
                applyButtonState();
              }, function() {
                setError('Unable to communicate with BeamNG Lua runtime.');
                scope.state.canRemove = false;
                scope.state.vehicleName = 'No vehicle detected';
                applyButtonState();
              });
          };

          scope.setEngineEmpty = function() {
            if (scope.state.busy || !scope.state.canRemove) {
              return;
            }
            scope.state.busy = true;
            applyButtonState();
            bngApi.engineLua('return extensions.core_RemoveEngine.setEngineEmpty()')
              .then(function(result) {
                scope.state.busy = false;
                var data = parseResult(result);
                if (data.success) {
                  setMessage(data.message || 'Engine removed.');
                } else {
                  setError(data.message || 'Failed to remove engine.');
                }
                applyButtonState();
                scope.refreshState();
              }, function() {
                scope.state.busy = false;
                setError('Failed to execute engine removal command.');
                applyButtonState();
              });
          };

          var pollPromise = $interval(scope.refreshState, 2000);
          scope.$on('$destroy', function() {
            if (pollPromise) {
              $interval.cancel(pollPromise);
            }
          });

          scope.refreshState();
        }
      };
    }]);
})();
