import * as THREE from 'three';

export function renderThumbnails<Id extends string>(
  renderer: THREE.WebGLRenderer,
  models: Partial<Record<Id, THREE.Group>>,
  ids: Id[],
) {
  const width = 168;
  const height = 112;
  const aspect = width / height;
  const target = new THREE.WebGLRenderTarget(width, height, { samples: 4 });
  target.texture.colorSpace = THREE.SRGBColorSpace;
  const previous = renderer.getRenderTarget();
  const shadowUpdate = renderer.shadowMap.needsUpdate;
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext('2d');
  const results = new Map<Id, string>();
  if (!context) {
    target.dispose();
    return results;
  }

  const scene = new THREE.Scene();
  scene.add(new THREE.HemisphereLight(0xfff4de, 0xb2c3b7, 2.0));
  const light = new THREE.DirectionalLight(0xffeac9, 2.2);
  light.position.set(-3, 6, 4);
  scene.add(light);
  const camera = new THREE.OrthographicCamera();
  const pixels = new Uint8Array(width * height * 4);
  const bitmap = context.createImageData(width, height);

  try {
    for (const id of ids) {
      const model = models[id];
      if (!model) continue;
      const object = model.clone(true);
      scene.add(object);
      const bounds = new THREE.Box3().setFromObject(object);
      if (!bounds.isEmpty()) {
        const center = bounds.getCenter(new THREE.Vector3());
        const size = bounds.getSize(new THREE.Vector3());
        const span = Math.max(size.y + size.z * 0.45, (size.x + size.z * 0.67) / aspect, 0.1) * 0.64;
        camera.left = -span * aspect;
        camera.right = span * aspect;
        camera.top = span;
        camera.bottom = -span;
        camera.near = 0.001;
        camera.far = 50;
        camera.position.set(3, 2.4, 5).multiplyScalar(Math.max(span, 0.5)).add(center);
        camera.lookAt(center);
        camera.updateProjectionMatrix();
        renderer.setRenderTarget(target);
        renderer.render(scene, camera);
        renderer.readRenderTargetPixels(target, 0, 0, width, height, pixels);
        const stride = width * 4;
        for (let y = 0; y < height; y++) {
          const offset = (height - y - 1) * stride;
          bitmap.data.set(pixels.subarray(offset, offset + stride), y * stride);
        }
        context.putImageData(bitmap, 0, 0);
        results.set(id, canvas.toDataURL('image/png'));
      }
      scene.remove(object);
    }
    return results;
  } finally {
    renderer.setRenderTarget(previous);
    renderer.shadowMap.needsUpdate = shadowUpdate;
    target.dispose();
  }
}
